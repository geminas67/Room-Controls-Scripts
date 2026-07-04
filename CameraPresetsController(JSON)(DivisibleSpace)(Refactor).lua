--[[
  Camera Preset Controller - Q-SYS Control Script
  Divisible Space Implementation
  Author: Nikolas Smith, Q-SYS
  Version: 6.0 (Flat module, Q-SYS architecture)
  Firmware Req: 10.0.0

  Per-room: btnCamPreset{N}[1..n], ledPresetMatch{N}, ledPresetSaved{N},
            devCams[N], routerOutput[N], compRoomControls[N]
  Shared: compcamRouter, txtJSONStorage
]]--

-- luacheck: globals Controls Timer Component rapidjson

-------------------[ Control Discovery ]-------------------
local function discoverNumRooms()
    for i = 1, 10 do
        if not Controls["btnCamPreset" .. i] then return i - 1 end
    end
    return 0
end

local function buildPerRoomControls(baseName, numRooms)
    local arr = {}
    for i = 1, numRooms do arr[i] = Controls[baseName .. i] end
    return #arr > 0 and arr or nil
end

local numRooms = discoverNumRooms()

-------------------[ Controls ]-------------------
local controls = {
    devCams = Controls.devCams,
    routerOutput = Controls.routerOutput,
    compRoomControls = Controls.compRoomControls,
    btnCamPreset = buildPerRoomControls("btnCamPreset", numRooms),
    ledPresetMatch = buildPerRoomControls("ledPresetMatch", numRooms),
    ledPresetSaved = buildPerRoomControls("ledPresetSaved", numRooms),
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus
}

-------------------[ Configuration ]-------------------
local config = {
    presetTolerance = 0.02,
    holdTime = 3.0,
    ledOnTime = 2.5,
    defaultPreset = 1,
    debounceDelay = 0.1
}

local componentTypes = {
    camera = "onvif_camera_operative",
    camRouter = "video_router",
    roomControls = "device_controller_script"
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
        end) then count = count + 1 end
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
const = {
    debug = true,
    roomName = "CameraPreset",
    clearString = "[Clear]"
}

-------------------[ State ]-------------------
local components = {
    cameras = {},
    presets = {},
    routers = {},
    roomControls = {}
}

local state = {
    longPressed = {},
    countdownTimers = {},
    ledTimers = {},
    debounceTimers = {},
    currentRouters = {},
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

local function discoverCameras(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then
        debugPrint("Invalid room index: " .. tostring(roomIdx), true)
        return {}
    end
    if not components.cameras[roomIdx] then components.cameras[roomIdx] = {} end
    local names = {}
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then debugPrint("Component discovery failed for room " .. roomIdx, true); return names end
    for _, comp in pairs(comps) do
        if comp.Type == componentTypes.camera and comp.Name and validateComponent(comp.Name) then
            table.insert(names, comp.Name)
            components.cameras[roomIdx][comp.Name] = Component.New(comp.Name)
            debugPrint(string.format("Room[%d] Camera found: %s (Source: Component Discovery)", roomIdx, comp.Name))
        end
    end
    table.sort(names)
    return names
end

local function initPresets(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return end
    local roomCams = components.cameras[roomIdx] or {}
    local names = {}
    for camName, _ in pairs(roomCams) do table.insert(names, camName) end
    if #names == 0 then return end
    local btnArr = controls.btnCamPreset[roomIdx] or {}
    local numPresets = isArr(btnArr) and #btnArr or 0
    if numPresets == 0 then return end
    for _, camName in pairs(names) do
        if not components.presets[camName] then
            components.presets[camName] = {}
            for presetIdx = 1, numPresets do components.presets[camName][presetIdx] = "0 0 0" end
            debugPrint(string.format("Room[%d] Presets initialized for %s", roomIdx, camName))
        end
    end
end

local function updateLEDsInternal(roomIdx)
    local function clearLEDs()
        local leds = controls.ledPresetMatch[roomIdx] or {}
        local arr = isArr(leds) and leds or {leds}
        for _, led in ipairs(arr) do setProp(led, "Boolean", false) end
    end
    if not controls.devCams or not controls.devCams[roomIdx] then return end
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then clearLEDs(); return end
    local cam = (components.cameras[roomIdx] or {})[camName]
    if not cam then clearLEDs(); return end
    if cam["is.moving"] and cam["is.moving"].Boolean then clearLEDs(); return end
    local current = cam["ptz.preset"] and cam["ptz.preset"].String or ""
    if current == "" or type(current) ~= "string" or current:match("^%s*$") then
        local now = os.clock()
        if not state.lastEmptyPresetLog or (now - state.lastEmptyPresetLog) > 5 then
            debugPrint(string.format("Room[%d] No preset data for %s", roomIdx, camName))
            state.lastEmptyPresetLog = now
        end
        clearLEDs()
        return
    end
    local saved = components.presets[camName] or {}
    local leds = controls.ledPresetMatch[roomIdx] or {}
    local arr = isArr(leds) and leds or {leds}
    for presetIdx, led in ipairs(arr) do
        local matches = saved[presetIdx] and presetsMatch(current, saved[presetIdx], config.presetTolerance)
        setProp(led, "Boolean", matches or false)
    end
end

local function updatePresetMatchLEDs(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return end
    if not state.debounceTimers[roomIdx] then state.debounceTimers[roomIdx] = Timer.New() end
    local timer = state.debounceTimers[roomIdx]
    timer:Stop()
    timer.EventHandler = function() updateLEDsInternal(roomIdx) end
    timer:Start(config.debounceDelay)
end

local function reloadJSON()
    if not loadJSON() then return false end
    for roomIdx = 1, numRooms do updatePresetMatchLEDs(roomIdx) end
    debugPrint("JSON reloaded from external source - all rooms synced")
    return true
end

local function savePreset(roomIdx, presetIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return false end
    if not controls.devCams or not controls.devCams[roomIdx] then return false end
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then debugPrint(string.format("Room[%d] No camera selected", roomIdx), true); return false end
    local cam = (components.cameras[roomIdx] or {})[camName]
    if not cam or not cam["ptz.preset"] then
        debugPrint(string.format("Room[%d] Invalid camera: %s", roomIdx, camName), true)
        return false
    end
    local currentPreset = cam["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        debugPrint(string.format("Room[%d] No preset data for %s", roomIdx, camName), true)
        return false
    end
    if not components.presets[camName] then components.presets[camName] = {} end
    local oldPreset = components.presets[camName][presetIdx] or "not set"
    components.presets[camName][presetIdx] = currentPreset
    debugPrint(string.format("Room[%d] Saved %s Preset[%d]: %s (was: %s) (Source: User Long Press)",
        roomIdx, camName, presetIdx, currentPreset, oldPreset))
    if not saveJSON() then debugPrint("JSON save failed", true) end
    return true
end

local function recallPreset(roomIdx, presetIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return false end
    if not controls.devCams or not controls.devCams[roomIdx] then return false end
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then return false end
    local cam = (components.cameras[roomIdx] or {})[camName]
    if not cam or not cam["ptz.preset"] then return false end
    local saved = components.presets[camName]
    if not saved or not saved[presetIdx] or saved[presetIdx] == "0 0 0" then
        debugPrint(string.format("Room[%d] Preset[%d] not saved for %s", roomIdx, presetIdx, camName), true)
        return false
    end
    cam["ptz.preset"].String = saved[presetIdx]
    debugPrint(string.format("Room[%d] Recalled %s Preset[%d]: %s (Source: User Button Press)",
        roomIdx, camName, presetIdx, saved[presetIdx]))
    return true
end

local function discoverRouters(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return end
    if not components.routers[roomIdx] then components.routers[roomIdx] = {} end
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then return end
    for _, comp in pairs(comps) do
        if comp.Type and comp.Type:match(componentTypes.camRouter) and comp.Name and validateComponent(comp.Name) then
            components.routers[roomIdx][comp.Name] = Component.New(comp.Name)
            debugPrint(string.format("Room[%d] Router found: %s", roomIdx, comp.Name))
        end
    end
end

local function discoverRoomControls(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return end
    if not controls.compRoomControls or not controls.compRoomControls[roomIdx] then return end
    local name = controls.compRoomControls[roomIdx].String
    if not name or name == "" then return end
    if validateComponent(name) then
        components.roomControls[roomIdx] = Component.New(name)
        debugPrint(string.format("Room[%d] Room controls found: %s", roomIdx, name))
    end
end

local function syncToCamRouter(roomIdx, router, key, camCtrl)
    if not router or not router[key] or not camCtrl then return false end
    debugPrint(string.format("Room[%d] Setting up sync monitor for router output: %s (Source: setupRouterSync)", roomIdx, key))
    router[key].EventHandler = function()
        local idx = router[key].Value
        local currentCam = camCtrl.String or "[none]"
        debugPrint(string.format("Room[%d] Router output %s changed: input=%s, current camera=%s (Source: Router Output EventHandler)",
            roomIdx, key, tostring(idx), currentCam))
        if not camCtrl.Choices then return end
        if idx and idx > 0 and idx <= #camCtrl.Choices then
            local newCam = camCtrl.Choices[idx]
            setProp(camCtrl, "Value", idx)
            camCtrl.String = newCam
            debugPrint(string.format("Room[%d] Camera switched: %s → %s via router output %s (Source: Router Sync)",
                roomIdx, currentCam, newCam, key))
            updatePresetMatchLEDs(roomIdx)
        end
    end
    if router[key].EventHandler then
        router[key].EventHandler()
        debugPrint(string.format("Room[%d] Router output %s handler registered and initialized ✓", roomIdx, key))
        return true
    end
    return false
end

local function setupRouterSync(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > numRooms then return false end
    if not controls.compcamRouter then return false end
    local routerName = controls.compcamRouter.String
    if not routerName or routerName == "" then return false end
    debugPrint(string.format("Room[%d] === setupRouterSync START === Router: %s", roomIdx, routerName))
    if state.currentRouters[roomIdx] then
        local oldOutKey = controls.routerOutput and controls.routerOutput[roomIdx] and controls.routerOutput[roomIdx].String or "select.1"
        local cleanedCount = cleanupHandlers(state.currentRouters[roomIdx], {oldOutKey})
        debugPrint(string.format("Room[%d] Cleaned up %d old handler(s) for output: %s", roomIdx, cleanedCount, oldOutKey))
    end
    local router = (components.routers[roomIdx] or {})[routerName]
    if not router then
        debugPrint(string.format("Room[%d] Router not found: %s", roomIdx, routerName), true)
        return false
    end
    state.currentRouters[roomIdx] = router
    local outKey = (controls.routerOutput and controls.routerOutput[roomIdx] and controls.routerOutput[roomIdx].String ~= "")
        and controls.routerOutput[roomIdx].String or "select.1"
    if not router[outKey] then
        debugPrint(string.format("Room[%d] Router '%s' does not have output '%s'", roomIdx, routerName, outKey), true)
        return false
    end
    if not controls.devCams or not controls.devCams[roomIdx] then return false end
    local success = syncToCamRouter(roomIdx, router, outKey, controls.devCams[roomIdx])
    debugPrint(string.format("Room[%d] === setupRouterSync END === Success: %s", roomIdx, tostring(success)))
    return success
end

local function setupCameraMonitoring(roomIdx, camNames)
    local cams = components.cameras[roomIdx] or {}
    for _, name in pairs(camNames) do
        local cam = cams[name]
        if cam then
            if cam["ptz.preset"] then
                cam["ptz.preset"].EventHandler = function() updatePresetMatchLEDs(roomIdx) end
                debugPrint(string.format("Room[%d] Monitoring position: %s", roomIdx, name))
            end
            if cam["is.moving"] then
                cam["is.moving"].EventHandler = function() updatePresetMatchLEDs(roomIdx) end
                debugPrint(string.format("Room[%d] Monitoring movement: %s", roomIdx, name))
            end
        end
    end
end

local function setupCameraChoices(roomIdx, camNames)
    if not controls.devCams or not controls.devCams[roomIdx] then return end
    setProp(controls.devCams[roomIdx], "Choices", camNames)
    debugPrint(string.format("Room[%d] Camera choices: %d available", roomIdx, #camNames))
    if controls.txtJSONStorage then controls.txtJSONStorage.IsDisabled = true end
    if #camNames > 0 then
        controls.devCams[roomIdx].String = camNames[1]
        controls.devCams[roomIdx].Value = 1
        debugPrint(string.format("Room[%d] Default camera: %s", roomIdx, camNames[1]))
        if recallPreset(roomIdx, config.defaultPreset) then
            debugPrint(string.format("Room[%d] Default preset %d recalled (Source: Initialization)", roomIdx, config.defaultPreset))
        end
    end
end

local function updateRouterChoices()
    if not controls.compcamRouter then return end
    local routerSet = {}
    for roomIdx = 1, numRooms do
        for name, _ in pairs(components.routers[roomIdx] or {}) do routerSet[name] = true end
    end
    local names = {}
    for name, _ in pairs(routerSet) do table.insert(names, name) end
    table.sort(names)
    table.insert(names, const.clearString)
    controls.compcamRouter.Choices = names
    if #names > 0 then
        controls.compcamRouter.String = names[1]
        debugPrint(string.format("Router choices updated: %d available (aggregated from %d rooms)", #names - 1, numRooms))
    end
end

local function updateRouterOutputChoices(roomIdx)
    if not controls.routerOutput or not controls.routerOutput[roomIdx] or not controls.compcamRouter then return end
    local routerName = controls.compcamRouter.String
    local router = (routerName ~= "" and routerName ~= const.clearString) and (components.routers[roomIdx] or {})[routerName]
    local outputs = {}
    if router then
        for k in pairs(router) do
            local n = type(k) == "string" and k:match("^select%.(%d+)$")
            if n then outputs[#outputs + 1] = { tonumber(n), k } end
        end
        table.sort(outputs, function(a, b) return a[1] < b[1] end)
        for i, v in ipairs(outputs) do outputs[i] = v[2] end
    end
    local out = controls.routerOutput[roomIdx]
    setProp(out, "Choices", outputs)
    local current = out.String or ""
    if not router or not router[current] then
        local newOutput = outputs[roomIdx] or outputs[1] or ""
        setProp(out, "String", newOutput)
        if newOutput ~= "" and current ~= newOutput then
            debugPrint(string.format("Room[%d] Router output: '%s' → '%s' (cache invalid)", roomIdx, current, newOutput))
        end
    end
end

local function handleSave(roomIdx, presetIdx)
    if not savePreset(roomIdx, presetIdx) then return end
    local leds = controls.ledPresetSaved and controls.ledPresetSaved[roomIdx]
    if leds then
        local arr = isArr(leds) and leds or {leds}
        if arr[presetIdx] then
            setProp(arr[presetIdx], "Boolean", true)
            state.ledTimers[roomIdx][presetIdx]:Start(config.ledOnTime)
        end
    end
    updatePresetMatchLEDs(roomIdx)
end

local function handleRecall(roomIdx, presetIdx)
    if not recallPreset(roomIdx, presetIdx) then return end
    updatePresetMatchLEDs(roomIdx)
end

local function initPresetButtons()
    if not controls.btnCamPreset then return end
    for roomIdx = 1, numRooms do
        if not controls.btnCamPreset[roomIdx] then goto continue end
        local btns = isArr(controls.btnCamPreset[roomIdx]) and controls.btnCamPreset[roomIdx] or {controls.btnCamPreset[roomIdx]}
        state.longPressed[roomIdx] = {}
        state.countdownTimers[roomIdx] = {}
        state.ledTimers[roomIdx] = {}
        for presetIdx, btn in ipairs(btns) do
            if btn then
                local rIdx, pIdx = roomIdx, presetIdx
                state.longPressed[roomIdx][presetIdx] = false
                state.countdownTimers[roomIdx][presetIdx] = Timer.New()
                state.ledTimers[roomIdx][presetIdx] = Timer.New()
                state.countdownTimers[roomIdx][presetIdx].EventHandler = function()
                    state.countdownTimers[rIdx][pIdx]:Stop()
                    if btns[pIdx] and btns[pIdx].Boolean then
                        state.longPressed[rIdx][pIdx] = true
                        handleSave(rIdx, pIdx)
                    end
                end
                state.ledTimers[roomIdx][presetIdx].EventHandler = function()
                    state.ledTimers[rIdx][pIdx]:Stop()
                    local leds = controls.ledPresetSaved and controls.ledPresetSaved[rIdx]
                    if leds then
                        local arr = isArr(leds) and leds or {leds}
                        if arr[pIdx] then setProp(arr[pIdx], "Boolean", false) end
                    end
                end
                btn.EventHandler = function()
                    if btns[pIdx].Boolean then
                        state.longPressed[rIdx][pIdx] = false
                        state.countdownTimers[rIdx][pIdx]:Start(config.holdTime)
                    else
                        state.countdownTimers[rIdx][pIdx]:Stop()
                        if not state.longPressed[rIdx][pIdx] then handleRecall(rIdx, pIdx) end
                    end
                end
            end
        end
        debugPrint(string.format("Room[%d] Registered %d preset button handlers", roomIdx, #btns))
        ::continue::
    end
end

local function validateControls()
    if not Controls.devCams then debugPrint("devCams control missing", true); return false end
    if not Controls.btnCamPreset1 then debugPrint("btnCamPreset1 control missing", true); return false end
    if not controls.btnCamPreset or not isArr(controls.btnCamPreset) then
        debugPrint("btnCamPreset per-room arrays not built", true)
        return false
    end
    if not controls.txtJSONStorage then debugPrint("txtJSONStorage required", true); return false end
    if isArr(controls.txtJSONStorage) then debugPrint("txtJSONStorage must be single control", true); return false end
    for roomIdx = 1, numRooms do
        if not controls.btnCamPreset[roomIdx] then
            debugPrint(string.format("btnCamPreset%d missing", roomIdx), true)
            return false
        end
        debugPrint(string.format("Room[%d] has %d preset buttons", roomIdx, #controls.btnCamPreset[roomIdx]))
    end
    debugPrint(string.format("Control validation passed - %d rooms", numRooms))
    return true
end

-------------------[ Events ]-------------------
local function registerEvents()
    debugPrint("Registering event handlers...")
    if controls.txtJSONStorage then
        bind(controls.txtJSONStorage, function()
            if not state.isSavingJSON then
                debugPrint("JSON changed externally - reloading all rooms (Source: External Instance)")
                reloadJSON()
            end
        end)
        debugPrint("Registered JSON sync handler")
    end
    if controls.devCams then
        local count = bindArray(controls.devCams, function(idx) updatePresetMatchLEDs(idx) end)
        debugPrint(string.format("Registered %d camera selection handlers", count))
    end
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            debugPrint(string.format("compcamRouter changed to: %s (Source: User Selection)", controls.compcamRouter.String or "[none]"))
            for roomIdx = 1, numRooms do
                updateRouterOutputChoices(roomIdx)
                setupRouterSync(roomIdx)
            end
        end)
        debugPrint("Registered shared router selector handler")
    end
    if controls.routerOutput then
        local count = bindArray(controls.routerOutput, function(idx, ctl)
            debugPrint(string.format("Room[%d] routerOutput changed to: %s (Source: User Selection)", idx, ctl.String or "[empty]"))
            setupRouterSync(idx)
        end)
        debugPrint(string.format("Registered %d router output handlers", count))
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
    debugPrint(string.format("Config: debugging=%s, rooms=%d, tolerance=%.3f, hold=%.1fs, led=%.1fs",
        tostring(const.debug), numRooms, config.presetTolerance, config.holdTime, config.ledOnTime))
    if not loadJSON() then debugPrint("No existing JSON - will create new preset structure") end
    for roomIdx = 1, numRooms do
        debugPrint(string.format("Initializing Room[%d]...", roomIdx))
        local cams = discoverCameras(roomIdx)
        if #cams == 0 then debugPrint(string.format("Room[%d] No cameras found", roomIdx), true)
        else for camIdx, name in ipairs(cams) do debugPrint(string.format("Room[%d] Camera[%d]: %s", roomIdx, camIdx, name)) end end
        discoverRouters(roomIdx)
        discoverRoomControls(roomIdx)
        initPresets(roomIdx)
        setupCameraMonitoring(roomIdx, cams)
        setupCameraChoices(roomIdx, cams)
    end
    updateRouterChoices()
    for roomIdx = 1, numRooms do updateRouterOutputChoices(roomIdx) end
    for roomIdx = 1, numRooms do setupRouterSync(roomIdx) end
    for roomIdx = 1, numRooms do updatePresetMatchLEDs(roomIdx) end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
    state.initialized = true
    debugPrint("=== Initialization Complete ===")
    debugPrint(string.format("Ready - %d rooms operational", numRooms))
end

local function cleanup()
    debugPrint("=== Cleanup Started ===")
    for roomIdx = 1, numRooms do
        if state.countdownTimers[roomIdx] then
            for _, timer in pairs(state.countdownTimers[roomIdx]) do if timer then timer:Stop() end end
        end
        if state.ledTimers[roomIdx] then
            for _, timer in pairs(state.ledTimers[roomIdx]) do if timer then timer:Stop() end end
        end
        if state.debounceTimers[roomIdx] then state.debounceTimers[roomIdx]:Stop() end
    end
    for roomIdx = 1, numRooms do
        for _, cam in pairs(components.cameras[roomIdx] or {}) do
            if cam then
                if cam["ptz.preset"] then cam["ptz.preset"].EventHandler = nil end
                if cam["is.moving"] then cam["is.moving"].EventHandler = nil end
            end
        end
    end
    state.initialized = false
    debugPrint("=== Cleanup Complete ===")
end

-------------------[ Public API ]-------------------
CameraPresetController = {
    savePreset = savePreset,
    recallPreset = recallPreset,
    updatePresetMatchLEDs = updatePresetMatchLEDs,
    saveJSON = saveJSON,
    reloadJSON = reloadJSON,
    cleanup = cleanup,
    numRooms = numRooms,
    config = config
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing CameraPresetController for " .. numRooms .. " rooms...")
    if numRooms == 0 then error("No rooms detected - check controls") end
    if not validateControls() then error("Control validation failed") end
    registerEvents()
    init()
end)

if ok then
    print("✓ CameraPresetController initialized - " .. numRooms .. " rooms")
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        controls.txtStatus.String = "INIT FAILED"
        controls.txtStatus.Value = 2
    end
end
