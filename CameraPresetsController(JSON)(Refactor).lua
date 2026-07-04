--[[
  Camera Preset Controller - Q-SYS Control Script
  Single Room Implementation
  Author: Nikolas Smith, Q-SYS
  Version: 7.0 (Flat module, Q-SYS architecture)
  Firmware Req: 10.0.0

  Features: Camera/preset management, JSON sync, router integration
]]--

-- luacheck: globals Controls Timer Component rapidjson CameraPresetController

-------------------[ Controls ]-------------------
local controls = {
    devCams = Controls.devCams,
    btnCamPreset = Controls.btnCamPreset,
    ledPresetMatch = Controls.ledPresetMatch,
    ledPresetSaved = Controls.ledPresetSaved,
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    routerOutput = Controls.routerOutput,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus
}

-------------------[ Configuration ]-------------------
local config = {
    presetTolerance = 0.03,
    holdTime = 3.0,
    ledOnTime = 2.5,
    defaultCamera = "devCam01",
    defaultPreset = 1,
    debounceDelay = 0.1
}

local componentTypes = {
    camera = "onvif_camera_operative",
    camRouter = "video_router"
}

rapidjson = require("rapidjson")

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    local ok = pcall(function() ctrl.EventHandler = handler end)
    return ok
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
        end) then
            count = count + 1
        end
    end
    return count
end

local function validateComponent(name)
    if not name or name == "" then return false end
    local ok, comp = pcall(Component.New, name)
    if not ok or not comp then return false end
    local ok2, ctrls = pcall(Component.GetControls, comp)
    return ok2 and ctrls and #ctrls > 0
end

local function cleanupHandlers(comp, ctrlNames)
    if not comp or not ctrlNames then return 0 end
    local cleaned = 0
    for _, name in ipairs(ctrlNames) do
        if comp[name] and comp[name].EventHandler then
            comp[name].EventHandler = nil
            cleaned = cleaned + 1
        end
    end
    return cleaned
end

-------------------[ Config ]-------------------
local const = {
    debug = true,
    roomName = "CameraPreset",
    clearString = "[Clear]"
}

-------------------[ State ]-------------------
local components = {
    cameras = {},
    presets = {},
    routers = {}
}

local state = {
    longPressed = {},
    countdownTimers = {},
    ledTimers = {},
    debounceTimer = Timer.New(),
    currentRouter = nil,
    isSavingJSON = false,
    initialized = false,
    lastEmptyPresetLog = 0,
    lastParseError = 0
}

-------------------[ Debug ]-------------------
local function debugPrint(str, isError)
    if isError or const.debug then
        print("[" .. const.roomName .. (isError and " ERROR" or "") .. "] " .. str)
    end
end

-------------------[ Functions ]-------------------
local function parsePreset(str)
    if not str or type(str) ~= "string" or str == "" then return nil, nil, nil end
    local clean = str:gsub("%s+", " "):match("^%s*(.-)%s*$")
    local pan, tilt, zoom = clean:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
    if pan and tilt and zoom then return tonumber(pan), tonumber(tilt), tonumber(zoom) end
    local parts = {}
    for part in clean:gmatch("([%d%.%-]+)") do table.insert(parts, part) end
    if #parts == 3 then return tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]) end
    return nil, nil, nil
end

local function presetsMatch(current, saved, tolerance)
    if not current or not saved or saved == "0 0 0" then return false end
    if current == saved then return true end
    local cp, ct, cz = parsePreset(current)
    local sp, st, sz = parsePreset(saved)
    if not (cp and ct and cz and sp and st and sz) then
        local now = os.clock()
        if not state.lastParseError or (now - state.lastParseError) > 5 then
            debugPrint(string.format("Parse failed - Curr: '%s', Saved: '%s'", tostring(current), tostring(saved)))
            state.lastParseError = now
        end
        return false
    end
    return math.abs(cp - sp) <= tolerance and math.abs(ct - st) <= tolerance and math.abs(cz - sz) <= tolerance
end

local function saveJSON()
    if not components.presets then debugPrint("No presets to save", true); return false end
    local ok, json = pcall(rapidjson.encode, components.presets, {pretty = true, sort_keys = true})
    if not ok then debugPrint("JSON encode failed: " .. tostring(json), true); return false end
    if json == controls.txtJSONStorage.String then return false end
    state.isSavingJSON = true
    controls.txtJSONStorage.String = json
    state.isSavingJSON = false
    debugPrint("JSON saved")
    return true
end

local function loadJSON()
    local str = controls.txtJSONStorage.String or ""
    if str == "" then debugPrint("JSON storage empty - using defaults"); return false end
    local ok, tbl = pcall(rapidjson.decode, str)
    if ok and type(tbl) == "table" then
        components.presets = tbl
        debugPrint("JSON loaded")
        return true
    end
    debugPrint("JSON decode failed: " .. tostring(tbl), true)
    return false
end

local function discoverCameras()
    components.cameras = {}
    local names = {}
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then debugPrint("Component discovery failed", true); return names end
    for _, comp in pairs(comps) do
        if comp.Type == componentTypes.camera and comp.Name and validateComponent(comp.Name) then
            table.insert(names, comp.Name)
            components.cameras[comp.Name] = Component.New(comp.Name)
            debugPrint(string.format("Camera found: %s (Source: Component Discovery)", comp.Name))
        end
    end
    table.sort(names)
    return names
end

local function purgeRemovedCameras()
    local changed = false
    for camName, _ in pairs(components.presets) do
        if not components.cameras[camName] then
            components.presets[camName] = nil
            debugPrint("Purged presets for removed camera: " .. camName)
            changed = true
        end
    end
    return changed
end

local function initPresets()
    local names = {}
    for camName, _ in pairs(components.cameras) do table.insert(names, camName) end
    if #names == 0 then return false end
    local btnArr = isArr(controls.btnCamPreset) and controls.btnCamPreset or {controls.btnCamPreset}
    local numPresets = #btnArr
    if numPresets == 0 then return false end
    local changed = purgeRemovedCameras()
    for _, camName in pairs(names) do
        if not components.presets[camName] then
            components.presets[camName] = {}
            for presetIdx = 1, numPresets do components.presets[camName][presetIdx] = "0 0 0" end
            debugPrint("Presets initialized for " .. camName)
            changed = true
        end
    end
    return changed
end

local function updateLEDsInternal()
    local function clearLEDs()
        local leds = isArr(controls.ledPresetMatch) and controls.ledPresetMatch or {controls.ledPresetMatch}
        for _, led in ipairs(leds) do setProp(led, "Boolean", false) end
    end
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then clearLEDs(); return end
    local cam = components.cameras[camName]
    if not cam then clearLEDs(); return end
    if cam["is.moving"] and cam["is.moving"].Boolean then clearLEDs(); return end
    local current = cam["ptz.preset"] and cam["ptz.preset"].String or ""
    if current == "" or type(current) ~= "string" or current:match("^%s*$") then
        local now = os.clock()
        if not state.lastEmptyPresetLog or (now - state.lastEmptyPresetLog) > 5 then
            debugPrint("No preset data for " .. camName)
            state.lastEmptyPresetLog = now
        end
        clearLEDs()
        return
    end
    local saved = components.presets[camName] or {}
    local leds = isArr(controls.ledPresetMatch) and controls.ledPresetMatch or {controls.ledPresetMatch}
    for presetIdx, led in ipairs(leds) do
        local matches = saved[presetIdx] and presetsMatch(current, saved[presetIdx], config.presetTolerance)
        setProp(led, "Boolean", matches or false)
    end
end

local function updatePresetMatchLEDs()
    state.debounceTimer:Stop()
    state.debounceTimer.EventHandler = function() updateLEDsInternal() end
    state.debounceTimer:Start(config.debounceDelay)
end

local function reloadJSON()
    if not loadJSON() then return false end
    updatePresetMatchLEDs()
    debugPrint("JSON reloaded from external source (Source: External Instance)")
    return true
end

local function savePreset(presetIdx)
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then debugPrint("No camera selected", true); return false end
    local cam = components.cameras[camName]
    if not cam or not cam["ptz.preset"] then
        debugPrint("Invalid camera: " .. camName, true)
        return false
    end
    local currentPreset = cam["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        debugPrint("No preset data for " .. camName, true)
        return false
    end
    if not components.presets[camName] then components.presets[camName] = {} end
    local oldPreset = components.presets[camName][presetIdx] or "not set"
    components.presets[camName][presetIdx] = currentPreset
    debugPrint(string.format("Saved %s Preset[%d]: %s (was: %s) (Source: User Long Press)",
        camName, presetIdx, currentPreset, oldPreset))
    if not saveJSON() then debugPrint("JSON save failed", true) end
    return true
end

local function recallPreset(presetIdx)
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then return false end
    local cam = components.cameras[camName]
    if not cam or not cam["ptz.preset"] then return false end
    local saved = components.presets[camName]
    if not saved or not saved[presetIdx] or saved[presetIdx] == "0 0 0" then
        debugPrint(string.format("Preset[%d] not saved for %s", presetIdx, camName), true)
        return false
    end
    cam["ptz.preset"].String = saved[presetIdx]
    debugPrint(string.format("Recalled %s Preset[%d]: %s (Source: User Button Press)",
        camName, presetIdx, saved[presetIdx]))
    return true
end

local function discoverRouters()
    components.routers = {}
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then return end
    for _, comp in pairs(comps) do
        if comp.Type and comp.Type:match(componentTypes.camRouter) and comp.Name and validateComponent(comp.Name) then
            components.routers[comp.Name] = Component.New(comp.Name)
            debugPrint("Router found: " .. comp.Name)
        end
    end
end

local function syncToCamRouter(router, key, camCtrl)
    if not router or not router[key] or not camCtrl then return false end
    debugPrint("Setting up sync monitor for router output: " .. key .. " (Source: setupRouterSync)")
    router[key].EventHandler = function()
        local idx = router[key].Value
        local currentCam = camCtrl.String or "[none]"
        debugPrint(string.format("Router output %s changed: input=%s, current camera=%s (Source: Router Output EventHandler)",
            key, tostring(idx), currentCam))
        if not camCtrl.Choices then return end
        if idx and idx > 0 and idx <= #camCtrl.Choices then
            local newCam = camCtrl.Choices[idx]
            setProp(camCtrl, "Value", idx)
            camCtrl.String = newCam
            debugPrint(string.format("Camera switched: %s → %s via router output %s (Source: Router Sync)",
                currentCam, newCam, key))
            updatePresetMatchLEDs()
        end
    end
    if router[key].EventHandler then
        router[key].EventHandler()
        debugPrint("Router output " .. key .. " handler registered and initialized ✓")
        return true
    end
    return false
end

local function setupRouterSync()
    if not controls.compcamRouter then return false end
    local routerName = controls.compcamRouter.String
    if not routerName or routerName == "" then return false end
    debugPrint("=== setupRouterSync START === Router: " .. routerName)
    if state.currentRouter then
        local oldOutKey = controls.routerOutput and controls.routerOutput.String or "select.1"
        local cleanedCount = cleanupHandlers(state.currentRouter, {oldOutKey})
        if cleanedCount > 0 then
            debugPrint("Cleaned up " .. cleanedCount .. " old handler(s) for output: " .. oldOutKey)
        end
    end
    local router = components.routers[routerName]
    if not router then
        debugPrint("Router not found: " .. routerName, true)
        return false
    end
    state.currentRouter = router
    local outKey = (controls.routerOutput and controls.routerOutput.String ~= "")
        and controls.routerOutput.String or "select.1"
    if not router[outKey] then
        debugPrint("Router '" .. routerName .. "' does not have output '" .. outKey .. "'", true)
        return false
    end
    if not controls.devCams then return false end
    local success = syncToCamRouter(router, outKey, controls.devCams)
    debugPrint("=== setupRouterSync END === Success: " .. tostring(success))
    return success
end

local function setupCameraMonitoring(camNames)
    for _, name in pairs(camNames) do
        local cam = components.cameras[name]
        if cam then
            if cam["ptz.preset"] then
                bind(cam["ptz.preset"], function() updatePresetMatchLEDs() end)
                debugPrint("Monitoring position: " .. name)
            end
            if cam["is.moving"] then
                bind(cam["is.moving"], function() updatePresetMatchLEDs() end)
                debugPrint("Monitoring movement: " .. name)
            end
        end
    end
end

local function setupCameraChoices(camNames)
    if not controls.devCams then return end
    setProp(controls.devCams, "Choices", camNames)
    debugPrint(string.format("Camera choices: %d available", #camNames))
    if controls.txtJSONStorage then controls.txtJSONStorage.IsDisabled = true end
    if #camNames > 0 then
        local defaultSet = false
        for camIdx, name in ipairs(camNames) do
            if name == config.defaultCamera then
                controls.devCams.String = name
                controls.devCams.Value = camIdx
                defaultSet = true
                break
            end
        end
        if not defaultSet then
            controls.devCams.String = camNames[1]
            controls.devCams.Value = 1
        end
        debugPrint("Default camera: " .. controls.devCams.String)
        if recallPreset(config.defaultPreset) then
            debugPrint(string.format("Default preset %d recalled (Source: Initialization)", config.defaultPreset))
        end
    end
end

local function updateRouterChoices()
    if not controls.compcamRouter then return end
    local names = {}
    for name, _ in pairs(components.routers) do table.insert(names, name) end
    table.sort(names)
    table.insert(names, const.clearString)
    controls.compcamRouter.Choices = names
    if #names > 0 then
        controls.compcamRouter.String = names[1]
        debugPrint(string.format("Router choices updated: %d available", #names - 1))
    end
end

local function updateRouterOutputChoices()
    if not controls.routerOutput or not controls.compcamRouter then return end
    local routerName = controls.compcamRouter.String
    local router = (routerName ~= "" and routerName ~= const.clearString) and components.routers[routerName]
    local outputs = {}
    if router then
        for k in pairs(router) do
            local n = type(k) == "string" and k:match("^select%.(%d+)$")
            if n then outputs[#outputs + 1] = { tonumber(n), k } end
        end
        table.sort(outputs, function(a, b) return a[1] < b[1] end)
        for i, v in ipairs(outputs) do outputs[i] = v[2] end
    end
    local out = controls.routerOutput
    setProp(out, "Choices", outputs)
    if not router or not router[out.String] then setProp(out, "String", outputs[1] or "") end
    if #outputs > 0 then debugPrint("Router output choices: " .. #outputs .. " available") end
end

local function handleSave(presetIdx)
    if not savePreset(presetIdx) then return end
    local leds = isArr(controls.ledPresetSaved) and controls.ledPresetSaved or {controls.ledPresetSaved}
    if leds[presetIdx] then
        setProp(leds[presetIdx], "Boolean", true)
        state.ledTimers[presetIdx]:Start(config.ledOnTime)
    end
    updatePresetMatchLEDs()
end

local function handleRecall(presetIdx)
    if not recallPreset(presetIdx) then return end
    updatePresetMatchLEDs()
end

local function initPresetButtons()
    if not controls.btnCamPreset then return end
    local btns = isArr(controls.btnCamPreset) and controls.btnCamPreset or {controls.btnCamPreset}
    for presetIdx, btn in ipairs(btns) do
        if btn then
            state.longPressed[presetIdx] = false
            state.countdownTimers[presetIdx] = Timer.New()
            state.ledTimers[presetIdx] = Timer.New()
            local pIdx = presetIdx
            state.countdownTimers[presetIdx].EventHandler = function()
                state.countdownTimers[pIdx]:Stop()
                if btns[pIdx] and btns[pIdx].Boolean then
                    state.longPressed[pIdx] = true
                    handleSave(pIdx)
                end
            end
            state.ledTimers[presetIdx].EventHandler = function()
                state.ledTimers[pIdx]:Stop()
                local leds = isArr(controls.ledPresetSaved) and controls.ledPresetSaved or {controls.ledPresetSaved}
                if leds[pIdx] then setProp(leds[pIdx], "Boolean", false) end
            end
            bind(btn, function()
                if btns[pIdx].Boolean then
                    state.longPressed[pIdx] = false
                    state.countdownTimers[pIdx]:Start(config.holdTime)
                else
                    state.countdownTimers[pIdx]:Stop()
                    if not state.longPressed[pIdx] then handleRecall(pIdx) end
                end
            end)
        end
    end
    debugPrint(string.format("Registered %d preset button handlers", #btns))
end

local function validateControls()
    if not Controls.devCams then debugPrint("devCams control missing", true); return false end
    if not Controls.btnCamPreset then debugPrint("btnCamPreset control missing", true); return false end
    if not controls.txtJSONStorage then debugPrint("txtJSONStorage required", true); return false end
    if isArr(controls.txtJSONStorage) then debugPrint("txtJSONStorage must be single control", true); return false end
    if isArr(controls.devCams) then debugPrint("devCams must be single control", true); return false end
    debugPrint("Control validation passed")
    return true
end

local function cleanup()
    debugPrint("=== Cleanup Started ===")
    for _, timer in pairs(state.countdownTimers) do if timer then timer:Stop() end end
    for _, timer in pairs(state.ledTimers) do if timer then timer:Stop() end end
    if state.debounceTimer then state.debounceTimer:Stop() end
    for _, cam in pairs(components.cameras) do
        if cam then
            if cam["ptz.preset"] then cam["ptz.preset"].EventHandler = nil end
            if cam["is.moving"] then cam["is.moving"].EventHandler = nil end
        end
    end
    state.initialized = false
    debugPrint("=== Cleanup Complete ===")
end

-------------------[ Events ]-------------------
local function registerEvents()
    debugPrint("Registering event handlers...")
    if controls.txtJSONStorage then
        bind(controls.txtJSONStorage, function()
            if not state.isSavingJSON then
                debugPrint("JSON changed externally - reloading (Source: External Instance)")
                reloadJSON()
            end
        end)
        debugPrint("Registered JSON sync handler")
    end
    if controls.devCams then
        bind(controls.devCams, function() updatePresetMatchLEDs() end)
        debugPrint("Registered camera selection handler")
    end
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            debugPrint("compcamRouter changed to: " .. (controls.compcamRouter.String or "[none]") .. " (Source: User Selection)")
            updateRouterOutputChoices()
            setupRouterSync()
        end)
        debugPrint("Registered router selector handler")
    end
    if controls.routerOutput then
        bind(controls.routerOutput, function()
            debugPrint("routerOutput changed to: " .. (controls.routerOutput.String or "[empty]") .. " (Source: User Selection)")
            setupRouterSync()
        end)
        debugPrint("Registered router output handler")
    end
    if controls.knbledOnTime then
        bind(controls.knbledOnTime, function()
            local val = controls.knbledOnTime.Value
            if val and val > 0 then config.ledOnTime = val; debugPrint("LED On Time: " .. val) end
        end)
    end
    if controls.knbHoldTime then
        bind(controls.knbHoldTime, function()
            local val = controls.knbHoldTime.Value
            if val and val > 0 then config.holdTime = val; debugPrint("Hold Time: " .. val) end
        end)
    end
    initPresetButtons()
end

-------------------[ Init ]-------------------
local function init()
    if state.initialized then return end
    debugPrint("=== Initialization Started ===")
    debugPrint(string.format("Config: debugging=%s, tolerance=%.3f, hold=%.1fs, led=%.1fs",
        tostring(const.debug), config.presetTolerance, config.holdTime, config.ledOnTime))
    if not loadJSON() then debugPrint("No existing JSON - will create new preset structure") end
    local cams = discoverCameras()
    if #cams == 0 then
        debugPrint("No cameras found", true)
        setProp(controls.txtStatus, "String", "No Cameras Found")
        setProp(controls.txtStatus, "Value", 2)
        return
    end
    for camIdx, name in ipairs(cams) do debugPrint(string.format("Camera[%d]: %s", camIdx, name)) end
    discoverRouters()
    if initPresets() then saveJSON() end
    setupCameraMonitoring(cams)
    setupCameraChoices(cams)
    updateRouterChoices()
    updateRouterOutputChoices()
    setupRouterSync()
    updatePresetMatchLEDs()
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
    state.initialized = true
    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
CameraPresetController = {
    savePreset = savePreset,
    recallPreset = recallPreset,
    updatePresetMatchLEDs = updatePresetMatchLEDs,
    saveJSON = saveJSON,
    reloadJSON = reloadJSON,
    cleanup = cleanup,
    config = config
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing CameraPresetController...")
    if not validateControls() then error("Control validation failed") end
    registerEvents()
    init()
end)

if ok then
    print("✓ CameraPresetController initialized - tolerance=" .. string.format("%.3f", config.presetTolerance)
        .. ", hold=" .. config.holdTime .. "s")
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end

--[[
  Usage (cross-script / console):
  CameraPresetController.savePreset(1)
  CameraPresetController.recallPreset(2)
  CameraPresetController.updatePresetMatchLEDs()
  CameraPresetController.reloadJSON()
  CameraPresetController.cleanup()
]]--
