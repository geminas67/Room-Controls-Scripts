--[[
  Camera Preset Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 8.0 (Simple architecture)
  Firmware Req: 10.0.0

  Camera/preset management, JSON sync, router integration.
]]--

-- luacheck: globals Controls Timer Component rapidjson

-------------------[ Configuration ]-------------------

local componentTypes = {
  camera = "onvif_camera_operative",
  camRouter = "video_router"
}

local presetTolerance = 0.03
local holdTime = 3.0
local ledOnTime = 2.5
local defaultCamera = "devCam01"
local defaultPreset = 1
local debounceDelay = 0.1

-------------------[ Constant Tables ]-------------------

compCams = {}
compPresets = {}
compRouters = {}
compRouterCurrent = nil

-------------------[ Constants ]-------------------

stateDebug = true
roomName = "CameraPreset"
strClear = "[Clear]"
isSavingJSON = false
longPressed = {}
countdownTimers = {}
ledTimers = {}
timerDebounce = Timer.New()
rapidjson = require("rapidjson")

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str, isError)
  if isError or stateDebug then
    print("[" .. roomName .. (isError and " ERROR" or "") .. "] " .. str)
  end
end

function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

function validComponent(name)
  if not name or name == "" then return false end
  local ok, comp = pcall(Component.New, name)
  if not ok or not comp then return false end
  local ok2, ctrls = pcall(Component.GetControls, comp)
  return ok2 and ctrls and #ctrls > 0
end

-------------------[ JSON ]-------------------

function saveJSON()
  local ok, json = pcall(rapidjson.encode, compPresets, {pretty = true, sort_keys = true})
  if not ok then debugMsg("JSON encode failed: " .. tostring(json), true); return false end
  if json == Controls.txtJSONStorage.String then return false end
  isSavingJSON = true
  Controls.txtJSONStorage.String = json
  isSavingJSON = false
  debugMsg("JSON saved")
  return true
end

function loadJSON()
  local str = Controls.txtJSONStorage.String or ""
  if str == "" then debugMsg("JSON storage empty - using defaults"); return false end
  local ok, tbl = pcall(rapidjson.decode, str)
  if ok and type(tbl) == "table" then
    compPresets = tbl
    debugMsg("JSON loaded")
    return true
  end
  debugMsg("JSON decode failed: " .. tostring(tbl), true)
  return false
end

function reloadJSON()
  if not loadJSON() then return end
  updatePresetLEDs()
  debugMsg("JSON reloaded from external source")
end

-------------------[ Preset Matching ]-------------------

function parsePreset(str)
  if not str or str == "" then return nil, nil, nil end
  local clean = str:gsub("%s+", " "):match("^%s*(.-)%s*$")
  local pan, tilt, zoom = clean:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
  if pan then return tonumber(pan), tonumber(tilt), tonumber(zoom) end
  local parts = {}
  for p in clean:gmatch("([%d%.%-]+)") do parts[#parts + 1] = p end
  if #parts == 3 then return tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]) end
  return nil, nil, nil
end

function presetsMatch(current, saved)
  if not current or not saved or saved == "0 0 0" or current == saved then
    return current == saved and current ~= nil
  end
  local cp, ct, cz = parsePreset(current)
  local sp, st, sz = parsePreset(saved)
  if not (cp and sp) then return false end
  return math.abs(cp - sp) <= presetTolerance
    and math.abs(ct - st) <= presetTolerance
    and math.abs(cz - sz) <= presetTolerance
end

-------------------[ Discovery ]-------------------

function discoverCameras()
  compCams = {}
  local names = {}
  local ok, comps = pcall(Component.GetComponents)
  if not ok then return names end
  for _, comp in pairs(comps) do
    if comp.Type == componentTypes.camera and validComponent(comp.Name) then
      names[#names + 1] = comp.Name
      compCams[comp.Name] = Component.New(comp.Name)
      debugMsg("Camera found: " .. comp.Name)
    end
  end
  table.sort(names)
  return names
end

function discoverRouters()
  compRouters = {}
  local ok, comps = pcall(Component.GetComponents)
  if not ok then return end
  for _, comp in pairs(comps) do
    if comp.Type and comp.Type:match(componentTypes.camRouter) and validComponent(comp.Name) then
      compRouters[comp.Name] = Component.New(comp.Name)
      debugMsg("Router found: " .. comp.Name)
    end
  end
end

-------------------[ Presets ]-------------------

function initPresets(camNames)
  local btns = isArr(Controls.btnCamPreset) and Controls.btnCamPreset or {Controls.btnCamPreset}
  if #camNames == 0 or #btns == 0 then return false end
  local changed = false
  for camName in pairs(compPresets) do
    if not compCams[camName] then
      compPresets[camName] = nil
      changed = true
    end
  end
  for _, camName in ipairs(camNames) do
    if not compPresets[camName] then
      compPresets[camName] = {}
      for i = 1, #btns do compPresets[camName][i] = "0 0 0" end
      changed = true
    end
  end
  return changed
end

function savePreset(idx)
  local camName = Controls.devCams.String
  local cam = compCams[camName]
  if camName == "" or not cam or not cam["ptz.preset"] then
    debugMsg("No camera selected", true); return false
  end
  local current = cam["ptz.preset"].String
  if not current or current == "" then debugMsg("No preset data for " .. camName, true); return false end
  compPresets[camName] = compPresets[camName] or {}
  compPresets[camName][idx] = current
  debugMsg(string.format("Saved %s Preset[%d]: %s", camName, idx, current))
  saveJSON()
  return true
end

function recallPreset(idx)
  local camName = Controls.devCams.String
  local cam = compCams[camName]
  local saved = compPresets[camName]
  if camName == "" or not cam or not cam["ptz.preset"] or not saved or not saved[idx] or saved[idx] == "0 0 0" then
    return false
  end
  cam["ptz.preset"].String = saved[idx]
  debugMsg(string.format("Recalled %s Preset[%d]: %s", camName, idx, saved[idx]))
  return true
end

-------------------[ Status ]-------------------

function updatePresetLEDs()
  local leds = isArr(Controls.ledPresetMatch) and Controls.ledPresetMatch or {Controls.ledPresetMatch}
  local camName = Controls.devCams.String
  local cam = compCams[camName]
  if camName == "" or not cam or (cam["is.moving"] and cam["is.moving"].Boolean) then
    for _, led in ipairs(leds) do led.Boolean = false end
    return
  end
  local current = cam["ptz.preset"] and cam["ptz.preset"].String or ""
  local saved = compPresets[camName] or {}
  for idx, led in ipairs(leds) do
    led.Boolean = current ~= "" and presetsMatch(current, saved[idx]) or false
  end
end

function debounceUpdateLEDs()
  timerDebounce:Stop()
  timerDebounce.EventHandler = updatePresetLEDs
  timerDebounce:Start(debounceDelay)
end

-------------------[ Router Sync ]-------------------

function setupRouterSync()
  local routerName = Controls.compcamRouter.String
  if routerName == "" then return false end
  local outKey = Controls.routerOutput.String ~= "" and Controls.routerOutput.String or "select.1"
  if compRouterCurrent and compRouterCurrent[outKey] then
    compRouterCurrent[outKey].EventHandler = nil
  end
  local router = compRouters[routerName]
  if not router or not router[outKey] then
    debugMsg("Router/output invalid: " .. routerName .. " / " .. outKey, true)
    return false
  end
  compRouterCurrent = router
  router[outKey].EventHandler = function()
    local idx = router[outKey].Value
    local choices = Controls.devCams.Choices
    if idx and choices and idx > 0 and idx <= #choices then
      Controls.devCams.Value = idx
      Controls.devCams.String = choices[idx]
      debugMsg("Camera switched via router: " .. choices[idx])
      debounceUpdateLEDs()
    end
  end
  router[outKey].EventHandler()
  return true
end

function updateRouterChoices()
  local names = {}
  for name in pairs(compRouters) do names[#names + 1] = name end
  table.sort(names)
  names[#names + 1] = strClear
  Controls.compcamRouter.Choices = names
  Controls.compcamRouter.String = names[1] or ""
end

function updateRouterOutputChoices()
  local routerName = Controls.compcamRouter.String
  local router = routerName ~= strClear and compRouters[routerName]
  local outputs = {}
  if router then
    for k in pairs(router) do
      local n = type(k) == "string" and k:match("^select%.(%d+)$")
      if n then outputs[#outputs + 1] = { tonumber(n), k } end
    end
    table.sort(outputs, function(a, b) return a[1] < b[1] end)
    for i, v in ipairs(outputs) do outputs[i] = v[2] end
  end
  Controls.routerOutput.Choices = outputs
  if not router or not router[Controls.routerOutput.String] then
    Controls.routerOutput.String = outputs[1] or ""
  end
end

-------------------[ Components ]-------------------

function setupCameraMonitoring(camNames)
  for _, name in ipairs(camNames) do
    local cam = compCams[name]
    if cam["ptz.preset"] then cam["ptz.preset"].EventHandler = debounceUpdateLEDs end
    if cam["is.moving"] then cam["is.moving"].EventHandler = debounceUpdateLEDs end
  end
end

function setupCameraChoices(camNames)
  Controls.devCams.Choices = camNames
  Controls.txtJSONStorage.IsDisabled = true
  if #camNames == 0 then return end
  local chosen = 1
  for i, name in ipairs(camNames) do
    if name == defaultCamera then chosen = i; break end
  end
  Controls.devCams.String = camNames[chosen]
  Controls.devCams.Value = chosen
  recallPreset(defaultPreset)
end

-------------------[ Preset Buttons ]-------------------

function handleSave(idx)
  if not savePreset(idx) then return end
  local leds = isArr(Controls.ledPresetSaved) and Controls.ledPresetSaved or {Controls.ledPresetSaved}
  if leds[idx] then
    leds[idx].Boolean = true
    ledTimers[idx]:Start(ledOnTime)
  end
  updatePresetLEDs()
end

function handleRecall(idx)
  if recallPreset(idx) then updatePresetLEDs() end
end

function initPresetButtons()
  local btns = isArr(Controls.btnCamPreset) and Controls.btnCamPreset or {Controls.btnCamPreset}
  for idx, btn in ipairs(btns) do
    longPressed[idx] = false
    countdownTimers[idx] = Timer.New()
    ledTimers[idx] = Timer.New()
    countdownTimers[idx].EventHandler = function()
      countdownTimers[idx]:Stop()
      if btns[idx].Boolean then
        longPressed[idx] = true
        handleSave(idx)
      end
    end
    ledTimers[idx].EventHandler = function()
      ledTimers[idx]:Stop()
      local leds = isArr(Controls.ledPresetSaved) and Controls.ledPresetSaved or {Controls.ledPresetSaved}
      if leds[idx] then leds[idx].Boolean = false end
    end
    btn.EventHandler = function()
      if btn.Boolean then
        longPressed[idx] = false
        countdownTimers[idx]:Start(holdTime)
      else
        countdownTimers[idx]:Stop()
        if not longPressed[idx] then handleRecall(idx) end
      end
    end
  end
end

-------------------[ Event Handlers ]-------------------

Controls.txtJSONStorage.EventHandler = function()
  if not isSavingJSON then reloadJSON() end
end

Controls.devCams.EventHandler = updatePresetLEDs

Controls.compcamRouter.EventHandler = function()
  updateRouterOutputChoices()
  setupRouterSync()
end

Controls.routerOutput.EventHandler = setupRouterSync

if Controls.knbledOnTime then
  Controls.knbledOnTime.EventHandler = function()
    if Controls.knbledOnTime.Value > 0 then ledOnTime = Controls.knbledOnTime.Value end
  end
end

if Controls.knbHoldTime then
  Controls.knbHoldTime.EventHandler = function()
    if Controls.knbHoldTime.Value > 0 then holdTime = Controls.knbHoldTime.Value end
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  loadJSON()
  local cams = discoverCameras()
  if #cams == 0 then
    debugMsg("No cameras found", true)
    Controls.txtStatus.String = "No Cameras Found"
    Controls.txtStatus.Value = 2
    return
  end
  discoverRouters()
  if initPresets(cams) then saveJSON() end
  setupCameraMonitoring(cams)
  setupCameraChoices(cams)
  updateRouterChoices()
  updateRouterOutputChoices()
  setupRouterSync()
  initPresetButtons()
  updatePresetLEDs()
  Controls.txtStatus.String = "OK"
  Controls.txtStatus.Value = 0
  debugMsg("Initialization complete")
end

funcInit()