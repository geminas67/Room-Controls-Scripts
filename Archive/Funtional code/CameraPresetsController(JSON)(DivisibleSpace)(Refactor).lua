--[[
  Camera Preset Controller - Q-SYS Control Script
  Divisible Space Implementation
  Author: Nikolas Smith, Q-SYS
  Version: 5.0 (Refactored - Event-Driven, Lean Architecture)
  Firmware Req: 10.0.0
  
  Per-room control structure:
    Room N: btnCamPreset{N}[1..n], ledPresetMatch{N}[1..n], ledPresetSaved{N}[1..n],
            devCams[N], routerOutput[N], compRoomControls[N]
  
  Shared: compcamRouter, txtJSONStorage (single source of truth)
  
  Features: Per-room camera/preset management, JSON sync, router integration
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
    for i = 1, numRooms do
        arr[i] = Controls[baseName .. i]
    end
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
    videoRouter = "video_router",
    roomControls = "device_controller_script"
}

rapidjson = require("rapidjson")

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and #t > 0
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if ctrl and handler then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local arr = isArr(ctrls) and ctrls or {ctrls}
    local count = 0
    for i, ctrl in ipairs(arr) do
        if ctrl then
            bind(ctrl, function(ctl)
                local ok, err = pcall(handler, i, ctl)
                if not ok then print("Handler error [" .. i .. "]: " .. tostring(err)) end
            end)
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

-------------------[ CameraPresetController ]-------------------
local CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

function CameraPresetController.new(userConfig)
    local self = setmetatable({}, CameraPresetController)
    
    self.debugging = userConfig and userConfig.debugging or true
    self.clearString = "[Clear]"
    self.numRooms = numRooms
    
    -- Merge config
    self.config = {}
    for k, v in pairs(config) do
        self.config[k] = (userConfig and userConfig[k]) or v
    end
    
    -- Components storage (per-room indexed)
    self.components = {
        cameras = {},      -- cameras[roomIdx][camName] = component
        presets = {},      -- presets[camName][presetIdx] = "pan tilt zoom"
        routers = {},      -- routers[roomIdx][routerName] = component
        roomControls = {}  -- roomControls[roomIdx] = component
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        debounceTimers = {},
        currentRouters = {},
        isSavingJSON = false,
        initialized = false,
        lastEmptyPresetLog = 0,
        lastMalformedPresetLog = 0,
        lastParseError = 0
    }
    
    return self
end

function CameraPresetController:debugPrint(msg)
    if self.debugging then print("[CameraPreset] " .. msg) end
end

function CameraPresetController:error(msg)
    print("[CameraPreset ERROR] " .. msg)
end

-------------------[ JSON Methods ]-------------------
function CameraPresetController:saveJSON()
    if not self.components.presets then
        self:error("No presets to save")
        return false
    end
    
    local ok, json = pcall(rapidjson.encode, self.components.presets, {pretty=true, sort_keys=true})
    if not ok then
        self:error("JSON encode failed: " .. tostring(json))
        return false
    end
    
    if json == controls.txtJSONStorage.String then return false end
    
    self.state.isSavingJSON = true
    controls.txtJSONStorage.String = json
    self.state.isSavingJSON = false
    self:debugPrint("JSON saved")
    return true
end

function CameraPresetController:loadJSON()
    local str = controls.txtJSONStorage.String or ""
    if str == "" then
        self:debugPrint("JSON storage empty - using defaults")
        return false
    end
    
    local ok, tbl = pcall(rapidjson.decode, str)
    if ok and type(tbl) == "table" then
        self.components.presets = tbl
        self:debugPrint("JSON loaded")
        return true
    end
    
    self:error("JSON decode failed: " .. tostring(tbl))
    return false
end

function CameraPresetController:reloadJSON()
    if not self:loadJSON() then return false end
    
    for i = 1, self.numRooms do
        self:updatePresetMatchLEDs(i)
    end
    self:debugPrint("JSON reloaded from external source - all rooms synced")
    return true
end

-------------------[ Camera Methods ]-------------------
function CameraPresetController:discoverCameras(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then
        self:error("Invalid room index: " .. tostring(roomIdx))
        return {}
    end
    
    if not self.components.cameras[roomIdx] then
        self.components.cameras[roomIdx] = {}
    end
    
    local names = {}
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then
        self:error("Component discovery failed for room " .. roomIdx)
        return names
    end
    
    -- CRITICAL: Discover ALL cameras for each room (no name filtering)
    -- This matches copy.lua behavior and ensures all cameras are available
    for _, comp in pairs(comps) do
        if comp.Type == componentTypes.camera and comp.Name then
            if validateComponent(comp.Name) then
                table.insert(names, comp.Name)
                self.components.cameras[roomIdx][comp.Name] = Component.New(comp.Name)
                self:debugPrint(string.format("Room[%d] Camera found: %s (Source: Component Discovery)", roomIdx, comp.Name))
            end
        end
    end
    
    table.sort(names)
    return names
end

function CameraPresetController:initPresets(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return end
    
    local roomCams = self.components.cameras[roomIdx] or {}
    local names = {}
    for n, _ in pairs(roomCams) do table.insert(names, n) end
    if #names == 0 then return end
    
    local btnArr = controls.btnCamPreset[roomIdx] or {}
    local numPresets = isArr(btnArr) and #btnArr or 0
    if numPresets == 0 then return end
    
    for _, camName in pairs(names) do
        if not self.components.presets[camName] then
            self.components.presets[camName] = {}
            for i = 1, numPresets do
                self.components.presets[camName][i] = "0 0 0"
            end
            self:debugPrint(string.format("Room[%d] Presets initialized for %s", roomIdx, camName))
        end
    end
end

function CameraPresetController:updatePresetMatchLEDs(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return end
    
    -- Debounce
    if not self.state.debounceTimers[roomIdx] then
        self.state.debounceTimers[roomIdx] = Timer.New()
    end
    local timer = self.state.debounceTimers[roomIdx]
    timer:Stop()
    -- luacheck: ignore 122
    timer.EventHandler = function() self:_updateLEDsInternal(roomIdx) end
    timer:Start(self.config.debounceDelay)
end

function CameraPresetController:_updateLEDsInternal(roomIdx)
    local clearLEDs = function()
        local leds = controls.ledPresetMatch[roomIdx] or {}
        local arr = isArr(leds) and leds or {leds}
        for _, led in ipairs(arr) do setProp(led, "Boolean", false) end
    end
    
    if not controls.devCams or not controls.devCams[roomIdx] then return end
    
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then clearLEDs(); return end
    
    local cam = (self.components.cameras[roomIdx] or {})[camName]
    if not cam then clearLEDs(); return end
    
    -- Skip if moving
    if cam["is.moving"] and cam["is.moving"].Boolean then clearLEDs(); return end
    
    local current = cam["ptz.preset"] and cam["ptz.preset"].String or ""
    if current == "" or type(current) ~= "string" or current:match("^%s*$") then
        local now = os.clock()
        if not self.state.lastEmptyPresetLog or (now - self.state.lastEmptyPresetLog) > 5 then
            self:debugPrint(string.format("Room[%d] No preset data for %s", roomIdx, camName))
            self.state.lastEmptyPresetLog = now
        end
        clearLEDs()
        return
    end
    
    local saved = self.components.presets[camName] or {}
    local leds = controls.ledPresetMatch[roomIdx] or {}
    local arr = isArr(leds) and leds or {leds}
    
    for i, led in ipairs(arr) do
        local matches = saved[i] and self:presetsMatch(current, saved[i], self.config.presetTolerance)
        setProp(led, "Boolean", matches or false)
    end
end

function CameraPresetController:presetsMatch(current, saved, tolerance)
    if not current or not saved or saved == "0 0 0" then return false end
    if current == saved then return true end
    
    local function parse(str)
        if not str or type(str) ~= "string" or str == "" then return nil, nil, nil end
        local clean = str:gsub("%s+", " "):match("^%s*(.-)%s*$")
        local pan, tilt, zoom = clean:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        if pan and tilt and zoom then return tonumber(pan), tonumber(tilt), tonumber(zoom) end
        
        local parts = {}
        for part in clean:gmatch("([%d%.%-]+)") do table.insert(parts, part) end
        if #parts == 3 then return tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]) end        
        return nil, nil, nil
    end
    local currentPan, currentTilt, currentZoom = parse(current)
    local savedPan, savedTilt, savedZoom = parse(saved)
    if not (currentPan and currentTilt and currentZoom and savedPan and savedTilt and savedZoom) then
        local now = os.clock()
        if not self.state.lastParseError or (now - self.state.lastParseError) > 5 then
            self:debugPrint(string.format("Parse failed - Curr: '%s', Saved: '%s'", tostring(current), tostring(saved)))
            self.state.lastParseError = now
        end
        return false
    end
    
    return math.abs(currentPan - savedPan) <= tolerance and math.abs(currentTilt - savedTilt) <= tolerance and math.abs(currentZoom - savedZoom) <= tolerance
end

function CameraPresetController:savePreset(roomIdx, presetIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return false end
    if not controls.devCams or not controls.devCams[roomIdx] then return false end
    
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then
        self:error(string.format("Room[%d] No camera selected", roomIdx))
        return false
    end
    
    local cam = (self.components.cameras[roomIdx] or {})[camName]
    if not cam or not cam["ptz.preset"] then
        self:error(string.format("Room[%d] Invalid camera: %s", roomIdx, camName))
        return false
    end
    
    local currentPreset = cam["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        self:error(string.format("Room[%d] No preset data for %s", roomIdx, camName))
        return false
    end
    
    if not self.components.presets[camName] then
        self.components.presets[camName] = {}
    end
    
    local oldPreset = self.components.presets[camName][presetIdx] or "not set"
    self.components.presets[camName][presetIdx] = currentPreset
    self:debugPrint(string.format("Room[%d] Saved %s Preset[%d]: %s (was: %s) (Source: User Long Press)", 
        roomIdx, camName, presetIdx, currentPreset, oldPreset))
    
    if not self:saveJSON() then
        self:error("JSON save failed")
    end
    
    return true
end

function CameraPresetController:recallPreset(roomIdx, presetIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return false end
    if not controls.devCams or not controls.devCams[roomIdx] then return false end
    
    local camName = controls.devCams[roomIdx].String or ""
    if camName == "" then return false end
    
    local cam = (self.components.cameras[roomIdx] or {})[camName]
    if not cam or not cam["ptz.preset"] then return false end
    
    local saved = self.components.presets[camName]
    if not saved or not saved[presetIdx] or saved[presetIdx] == "0 0 0" then
        self:error(string.format("Room[%d] Preset[%d] not saved for %s", roomIdx, presetIdx, camName))
        return false
    end
    
    cam["ptz.preset"].String = saved[presetIdx]
    self:debugPrint(string.format("Room[%d] Recalled %s Preset[%d]: %s (Source: User Button Press)", 
        roomIdx, camName, presetIdx, saved[presetIdx]))
    return true
end

-------------------[ Router Methods ]-------------------
function CameraPresetController:discoverRouters(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return end
    
    if not self.components.routers[roomIdx] then
        self.components.routers[roomIdx] = {}
    end
    
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then return end
    
    for _, comp in pairs(comps) do
        if comp.Type and comp.Type:match(componentTypes.videoRouter) and comp.Name then
            if validateComponent(comp.Name) then
                self.components.routers[roomIdx][comp.Name] = Component.New(comp.Name)
                self:debugPrint(string.format("Room[%d] Router found: %s", roomIdx, comp.Name))
            end
        end
    end
end

function CameraPresetController:discoverRoomControls(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then return end
    if not controls.compRoomControls or not controls.compRoomControls[roomIdx] then return end
    
    local name = controls.compRoomControls[roomIdx].String
    if not name or name == "" then return end
    
    if validateComponent(name) then
        self.components.roomControls[roomIdx] = Component.New(name)
        self:debugPrint(string.format("Room[%d] Room controls found: %s", roomIdx, name))
    end
end

function CameraPresetController:setupRouterSync(roomIdx)
    if not roomIdx or roomIdx < 1 or roomIdx > self.numRooms then 
        self:debugPrint(string.format("setupRouterSync: Invalid room index %s", tostring(roomIdx)))
        return false 
    end
    if not controls.compcamRouter then 
        self:debugPrint(string.format("Room[%d] setupRouterSync: compcamRouter control not available", roomIdx))
        return false 
    end
    
    local routerName = controls.compcamRouter.String
    if not routerName or routerName == "" then 
        self:debugPrint(string.format("Room[%d] setupRouterSync: No router selected in compcamRouter", roomIdx))
        return false 
    end
    
    self:debugPrint(string.format("Room[%d] === setupRouterSync START === Router: %s", roomIdx, routerName))
    
    -- Cleanup old handlers
    if self.state.currentRouters[roomIdx] then
        local oldOutKey = controls.routerOutput and controls.routerOutput[roomIdx] and controls.routerOutput[roomIdx].String or "select.1"
        local cleanedCount = cleanupHandlers(self.state.currentRouters[roomIdx], {oldOutKey})
        self:debugPrint(string.format("Room[%d] Cleaned up %d old handler(s) for output: %s", roomIdx, cleanedCount, oldOutKey))
    end
    
    local router = (self.components.routers[roomIdx] or {})[routerName]
    if not router then
        self:error(string.format("Room[%d] Router not found in components: %s", roomIdx, routerName))
        return false
    end
    
    self.state.currentRouters[roomIdx] = router
    
    -- Get output control (dynamic or fallback to select.1)
    local outKey
    if controls.routerOutput and controls.routerOutput[roomIdx] and controls.routerOutput[roomIdx].String ~= "" then
        outKey = controls.routerOutput[roomIdx].String
        self:debugPrint(string.format("Room[%d] Using routerOutput control value: %s", roomIdx, outKey))
    else
        outKey = "select.1"
        self:debugPrint(string.format("Room[%d] Using fallback output: %s (routerOutput not set)", roomIdx, outKey))
    end
    
    -- Verify router has this output
    if not router[outKey] then
        self:error(string.format("Room[%d] Router '%s' does not have output control '%s'", roomIdx, routerName, outKey))
        return false
    end
    
    if not controls.devCams or not controls.devCams[roomIdx] then 
        self:error(string.format("Room[%d] devCams control not available", roomIdx))
        return false 
    end
    
    self:debugPrint(string.format("Room[%d] Connecting: Router[%s].%s → devCams[%d]", roomIdx, routerName, outKey, roomIdx))
    local success = self:syncCamWithRouter(roomIdx, router, outKey, controls.devCams[roomIdx])
    self:debugPrint(string.format("Room[%d] === setupRouterSync END === Success: %s", roomIdx, tostring(success)))
    
    return success
end

function CameraPresetController:syncCamWithRouter(roomIdx, router, key, camCtrl)
    if not router or not router[key] or not camCtrl then 
        self:debugPrint(string.format("Room[%d] syncCamWithRouter failed - missing params (router=%s, key=%s, camCtrl=%s)", 
            roomIdx, tostring(router ~= nil), tostring(key), tostring(camCtrl ~= nil)))
        return false 
    end
    
    -- Log which router output is being monitored for which room
    self:debugPrint(string.format("Room[%d] Setting up sync monitor for router output: %s (Source: setupRouterSync)", 
        roomIdx, key))
    
    -- Direct EventHandler assignment for reliability
    -- luacheck: ignore 122
    router[key].EventHandler = function()
        local idx = router[key].Value
        local currentCam = camCtrl.String or "[none]"
        
        self:debugPrint(string.format("Room[%d] Router output %s changed: input=%s, current camera=%s (Source: Router Output EventHandler)", 
            roomIdx, key, tostring(idx), currentCam))
        
        if not camCtrl.Choices then 
            self:debugPrint(string.format("Room[%d] Camera choices not initialized yet", roomIdx))
            return 
        end
        
        if idx and idx > 0 and idx <= #camCtrl.Choices then
            local newCam = camCtrl.Choices[idx]
            if setProp(camCtrl, "Value", idx) then
                camCtrl.String = newCam
                self:debugPrint(string.format("Room[%d] Camera switched: %s → %s via router output %s (Source: Router Sync)", 
                    roomIdx, currentCam, newCam, key))
            else
                self:debugPrint(string.format("Room[%d] Camera already set to %s (no change needed)", roomIdx, newCam))
            end
            self:updatePresetMatchLEDs(roomIdx)
        else
            self:debugPrint(string.format("Room[%d] Invalid router input: idx=%s, choices=%d", 
                roomIdx, tostring(idx), #camCtrl.Choices))
        end
    end
    
    -- Initialize - trigger handler to sync initial state
    if router[key].EventHandler then
        self:debugPrint(string.format("Room[%d] Initializing router output %s handler...", roomIdx, key))
        router[key].EventHandler()
        self:debugPrint(string.format("Room[%d] Router output %s handler registered and initialized ✓", roomIdx, key))
        return true
    end
    
    return false
end

-------------------[ Control Validation & Discovery ]-------------------
function CameraPresetController:discoverNumRooms()
    local maxLen = 0
    
    local function countArray(ctrl)
        if not ctrl then return 0 end
        for i = 1, 10 do
            if not ctrl[i] then return i - 1 end
        end
        return 10
    end
    
    if controls.devCams then maxLen = math.max(maxLen, countArray(controls.devCams)) end
    if controls.routerOutput then maxLen = math.max(maxLen, countArray(controls.routerOutput)) end
    if controls.btnCamPreset then maxLen = math.max(maxLen, #controls.btnCamPreset) end
    
    if maxLen == 0 then
        self:error("No rooms discovered")
    else
        self:debugPrint(string.format("Discovered %d rooms", maxLen))
    end
    
    return maxLen
end

function CameraPresetController:validateControls()
    if not Controls.devCams then
        self:error("devCams control missing")
        return false
    end
    
    if not Controls.btnCamPreset1 then
        self:error("btnCamPreset1 control missing")
        return false
    end
    
    if not controls.btnCamPreset or not isArr(controls.btnCamPreset) then
        self:error("btnCamPreset per-room arrays not built")
        return false
    end
    
    if not controls.txtJSONStorage then
        self:error("txtJSONStorage required")
        return false
    end
    
    if isArr(controls.txtJSONStorage) then
        self:error("txtJSONStorage must be single control, not array")
        return false
    end
    
    for i = 1, self.numRooms do
        if not controls.btnCamPreset[i] then
            self:error(string.format("btnCamPreset%d missing", i))
            return false
        end
        self:debugPrint(string.format("Room[%d] has %d preset buttons", i, #controls.btnCamPreset[i]))
    end
    
    self:debugPrint(string.format("Control validation passed - %d rooms", self.numRooms))
    return true
end

-------------------[ Initialization ]-------------------
function CameraPresetController:init()
    if self.state.initialized then return end
    
    self:debugPrint("=== Initialization Started ===")
    self:debugPrint(string.format("Config: debugging=%s, rooms=%d, tolerance=%.3f, hold=%.1fs, led=%.1fs", 
        tostring(self.debugging), self.numRooms, self.config.presetTolerance, 
        self.config.holdTime, self.config.ledOnTime))
    
    -- Load JSON
    if not self:loadJSON() then
        self:debugPrint("No existing JSON - will create new preset structure")
    end
    
    -- Per-room initialization
    for i = 1, self.numRooms do
        self:debugPrint(string.format("Initializing Room[%d]...", i))
        
        local cams = self:discoverCameras(i)
        if #cams == 0 then
            self:error(string.format("Room[%d] No cameras found", i))
        else
            for j, name in ipairs(cams) do
                self:debugPrint(string.format("Room[%d] Camera[%d]: %s", i, j, name))
            end
        end
        
        self:discoverRouters(i)
        self:discoverRoomControls(i)
        self:initPresets(i)
        self:setupCameraMonitoring(i, cams)
        self:setupCameraChoices(i, cams)
    end
    
    -- Populate shared router choices (aggregated from all rooms)
    self:updateRouterChoices()
    
    -- Update per-room router outputs
    for i = 1, self.numRooms do
        self:updateRouterOutputChoices(i)
    end
    
    -- Router sync (after UI populated)
    for i = 1, self.numRooms do
        self:setupRouterSync(i)
    end
    
    -- Initial LED updates
    for i = 1, self.numRooms do
        self:updatePresetMatchLEDs(i)
    end
    
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
    
    self.state.initialized = true
    self:debugPrint("=== Initialization Complete ===")
    self:debugPrint(string.format("Ready - %d rooms operational", self.numRooms))
end

-------------------[ Event Registration ]-------------------
function CameraPresetController:registerEvents()
    self:debugPrint("Registering event handlers...")
    
    -- JSON cross-instance sync
    if controls.txtJSONStorage then
        -- luacheck: ignore 122
        controls.txtJSONStorage.EventHandler = function()
            if not self.state.isSavingJSON then
                self:debugPrint("JSON changed externally - reloading all rooms (Source: External Instance)")
                self:reloadJSON()
            end
        end
        self:debugPrint("Registered JSON sync handler")
    end
    
    -- Camera selection handlers (per-room)
    if controls.devCams then
        local count = bindArray(controls.devCams, function(idx, ctl)
            self:updatePresetMatchLEDs(idx)
        end)
        self:debugPrint(string.format("Registered %d camera selection handlers", count))
    end
    
    -- Shared router selector
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            local selectedRouter = controls.compcamRouter.String or "[none]"
            self:debugPrint(string.format("=== compcamRouter changed to: %s (Source: User Selection) ===", selectedRouter))
            self:debugPrint("Updating router output choices and sync for all rooms...")
            for i = 1, self.numRooms do
                self:debugPrint(string.format("  → Room[%d]: Updating output choices...", i))
                self:updateRouterOutputChoices(i)
                self:debugPrint(string.format("  → Room[%d]: Re-establishing router sync...", i))
                self:setupRouterSync(i)
            end
            self:debugPrint("=== Router change complete for all rooms ===")
        end)
        self:debugPrint("Registered shared router selector handler")
    end
    
    -- Router output handlers (per-room)
    if controls.routerOutput then
        local count = bindArray(controls.routerOutput, function(idx, ctl)
            local outputKey = ctl.String or "[empty]"
            self:debugPrint(string.format("Room[%d] routerOutput changed to: %s (Source: User Selection)", idx, outputKey))
            self:debugPrint(string.format("Room[%d] Re-establishing router sync with new output...", idx))
            self:setupRouterSync(idx)
        end)
        self:debugPrint(string.format("Registered %d router output handlers", count))
    end
    
    -- Config knobs
    if controls.knbledOnTime then
        -- luacheck: ignore 122
        controls.knbledOnTime.EventHandler = function()
            local val = controls.knbledOnTime.Value
            if val and val > 0 then
                self.config.ledOnTime = val
                self:debugPrint("LED On Time: " .. val)
            end
        end
    end
    
    if controls.knbHoldTime then
        -- luacheck: ignore 122
        controls.knbHoldTime.EventHandler = function()
            local val = controls.knbHoldTime.Value
            if val and val > 0 then
                self.config.holdTime = val
                self:debugPrint("Hold Time: " .. val)
            end
        end
    end
    
    self:initPresetButtons()
end

function CameraPresetController:initPresetButtons()
    if not controls.btnCamPreset then return end
    
    for roomIdx = 1, self.numRooms do
        if not controls.btnCamPreset[roomIdx] then goto continue end
        
        local btns = isArr(controls.btnCamPreset[roomIdx]) and controls.btnCamPreset[roomIdx] or {controls.btnCamPreset[roomIdx]}
        
        self.state.longPressed[roomIdx] = {}
        self.state.countdownTimers[roomIdx] = {}
        self.state.ledTimers[roomIdx] = {}
        
        for presetIdx, btn in ipairs(btns) do
            if btn then
                self.state.longPressed[roomIdx][presetIdx] = false
                self.state.countdownTimers[roomIdx][presetIdx] = Timer.New()
                self.state.ledTimers[roomIdx][presetIdx] = Timer.New()
                
                -- Long press timer
                -- luacheck: ignore 122
                self.state.countdownTimers[roomIdx][presetIdx].EventHandler = function()
                    print("Long press timer started for room " .. roomIdx .. " preset " .. presetIdx)
                    self.state.countdownTimers[roomIdx][presetIdx]:Stop()
                    if btns[presetIdx] and btns[presetIdx].Boolean then
                        self.state.longPressed[roomIdx][presetIdx] = true
                        self:handleSave(roomIdx, presetIdx)
                    end
                end
                
                -- LED flash timer
                -- luacheck: ignore 122
                self.state.ledTimers[roomIdx][presetIdx].EventHandler = function()
                    self.state.ledTimers[roomIdx][presetIdx]:Stop()
                    local leds = controls.ledPresetSaved and controls.ledPresetSaved[roomIdx]
                    if leds then
                        local arr = isArr(leds) and leds or {leds}
                        if arr[presetIdx] then setProp(arr[presetIdx], "Boolean", false) end
                    end
                end
                
                -- Button handler
                -- luacheck: ignore 122
                btn.EventHandler = function()
                    if btns[presetIdx].Boolean then
                        self.state.longPressed[roomIdx][presetIdx] = false
                        self.state.countdownTimers[roomIdx][presetIdx]:Start(self.config.holdTime)
                    else
                        self.state.countdownTimers[roomIdx][presetIdx]:Stop()
                        if not self.state.longPressed[roomIdx][presetIdx] then
                            self:handleRecall(roomIdx, presetIdx)
                        end
                    end
                end
            end
        end
        
        self:debugPrint(string.format("Room[%d] Registered %d preset button handlers", roomIdx, #btns))
        ::continue::
    end
end

function CameraPresetController:handleSave(roomIdx, presetIdx)
    if not self:savePreset(roomIdx, presetIdx) then return end
    
    -- Flash LED
    local leds = controls.ledPresetSaved and controls.ledPresetSaved[roomIdx]
    if leds then
        local arr = isArr(leds) and leds or {leds}
        if arr[presetIdx] then
            setProp(arr[presetIdx], "Boolean", true)
            self.state.ledTimers[roomIdx][presetIdx]:Start(self.config.ledOnTime)
        end
    end
    
    self:updatePresetMatchLEDs(roomIdx)
end

function CameraPresetController:handleRecall(roomIdx, presetIdx)
    if not self:recallPreset(roomIdx, presetIdx) then return end
    self:updatePresetMatchLEDs(roomIdx)
end

function CameraPresetController:setupCameraMonitoring(roomIdx, camNames)
    local cams = self.components.cameras[roomIdx] or {}
    for _, name in pairs(camNames) do
        local cam = cams[name]
        if cam then
            if cam["ptz.preset"] then
                -- luacheck: ignore 122
                cam["ptz.preset"].EventHandler = function() self:updatePresetMatchLEDs(roomIdx) end
                self:debugPrint(string.format("Room[%d] Monitoring position: %s", roomIdx, name))
            end
            if cam["is.moving"] then
                -- luacheck: ignore 122
                cam["is.moving"].EventHandler = function() self:updatePresetMatchLEDs(roomIdx) end
                self:debugPrint(string.format("Room[%d] Monitoring movement: %s", roomIdx, name))
            end
        end
    end
end

function CameraPresetController:setupCameraChoices(roomIdx, camNames)
    if not controls.devCams or not controls.devCams[roomIdx] then return end
    
    setProp(controls.devCams[roomIdx], "Choices", camNames)
    self:debugPrint(string.format("Room[%d] Camera choices: %d available", roomIdx, #camNames))
    
    -- Disable JSON (shared, not user-editable)
    if controls.txtJSONStorage then
        controls.txtJSONStorage.IsDisabled = true
    end
    
    -- Set default
    if #camNames > 0 then
        controls.devCams[roomIdx].String = camNames[1]
        controls.devCams[roomIdx].Value = 1
        self:debugPrint(string.format("Room[%d] Default camera: %s", roomIdx, camNames[1]))
        self:recallDefaultPreset(roomIdx)
    end
end

function CameraPresetController:recallDefaultPreset(roomIdx)
    if not controls.devCams or not controls.devCams[roomIdx] then return end
    local cam = controls.devCams[roomIdx].String or ""
    if cam == "" then return end
    
    if self:recallPreset(roomIdx, self.config.defaultPreset) then
        self:debugPrint(string.format("Room[%d] Default preset %d recalled for %s (Source: Initialization)", 
            roomIdx, self.config.defaultPreset, cam))
    end
end

function CameraPresetController:updateRouterChoices()
    if not controls.compcamRouter then return end
    
    -- Aggregate unique routers from all rooms (compcamRouter is shared)
    local routerSet = {}
    for roomIdx = 1, self.numRooms do
        for name, _ in pairs(self.components.routers[roomIdx] or {}) do
            routerSet[name] = true
        end
    end
    
    -- Convert set to sorted array
    local names = {}
    for name, _ in pairs(routerSet) do
        table.insert(names, name)
    end
    table.sort(names)
    table.insert(names, self.clearString)
    
    controls.compcamRouter.Choices = names
    if #names > 0 then
        controls.compcamRouter.String = names[1]
        self:debugPrint(string.format("Router choices updated: %d available (aggregated from %d rooms)", #names - 1, self.numRooms))
    end
end

function CameraPresetController:updateRouterOutputChoices(roomIdx)
    if not controls.routerOutput or not controls.routerOutput[roomIdx] or not controls.compcamRouter then 
        self:debugPrint(string.format("Room[%d] updateRouterOutputChoices: Missing required controls", roomIdx))
        return 
    end
    
    local routerName = controls.compcamRouter.String
    self:debugPrint(string.format("Room[%d] updateRouterOutputChoices: Router='%s'", roomIdx, routerName or "[none]"))
    
    if not routerName or routerName == "" or routerName == self.clearString then
        controls.routerOutput[roomIdx].Choices = {}
        controls.routerOutput[roomIdx].String = ""
        self:debugPrint(string.format("Room[%d] Router output cleared (no router selected)", roomIdx))
        return
    end
    
    local roomRouters = self.components.routers[roomIdx] or {}
    local router = roomRouters[routerName]
    if not router then
        controls.routerOutput[roomIdx].Choices = {}
        controls.routerOutput[roomIdx].String = ""
        self:debugPrint(string.format("Room[%d] Router '%s' not found in room components", roomIdx, routerName))
        return
    end
    
    -- Build output list
    local outputNames = {}
    for name, _ in pairs(router) do
        if type(name) == "string" and name:match("^select%.%d+$") then
            table.insert(outputNames, name)
        end
    end
    
    -- Sort numerically
    table.sort(outputNames, function(a, b)
        return tonumber(a:match("%.(%d+)$")) < tonumber(b:match("%.(%d+)$"))
    end)
    
    if #outputNames > 0 then
        self:debugPrint(string.format("Room[%d] Found %d router outputs: [%s]", 
            roomIdx, #outputNames, table.concat(outputNames, ", ")))
        
        setProp(controls.routerOutput[roomIdx], "Choices", outputNames)
        
        -- Validate cached value
        local currentRouterOutput = controls.routerOutput[roomIdx].String or "[empty]"
        local isValid = false
        for _, outputName in ipairs(outputNames) do
            if outputName == currentRouterOutput then isValid = true; break end
        end
        
        if not isValid then
            local newOutput = outputNames[roomIdx] or outputNames[1]  -- Try to match room index, else use first
            controls.routerOutput[roomIdx].String = newOutput
            self:debugPrint(string.format("Room[%d] Router output changed: '%s' → '%s' (cache invalid or room-specific assignment)", 
                roomIdx, currentRouterOutput, newOutput))
        else
            self:debugPrint(string.format("Room[%d] Router output retained: '%s' (valid)", roomIdx, currentRouterOutput))
        end
    else
        self:debugPrint(string.format("Room[%d] No router outputs found - using fallback", roomIdx))
        controls.routerOutput[roomIdx].Choices = {"select.1"}
        controls.routerOutput[roomIdx].String = "select.1"
    end
end

-------------------[ Cleanup ]-------------------
function CameraPresetController:cleanup()
    self:debugPrint("=== Cleanup Started ===")
    
    -- Stop timers
    for roomIdx = 1, self.numRooms do
        if self.state.countdownTimers[roomIdx] then
            for _, t in pairs(self.state.countdownTimers[roomIdx]) do if t then t:Stop() end end
        end
        if self.state.ledTimers[roomIdx] then
            for _, timer in pairs(self.state.ledTimers[roomIdx]) do if timer then timer:Stop() end end
        end
        if self.state.debounceTimers[roomIdx] then
            self.state.debounceTimers[roomIdx]:Stop()
        end
    end
    
    -- Clear handlers
    for roomIdx = 1, self.numRooms do
        for _, cam in pairs(self.components.cameras[roomIdx] or {}) do
            if cam then
                if cam["ptz.preset"] then cam["ptz.preset"].EventHandler = nil end
                if cam["is.moving"] then cam["is.moving"].EventHandler = nil end
            end
        end
    end
    
    self.state.initialized = false
    self:debugPrint("=== Cleanup Complete ===")
end

-------------------[ Factory & Initialization ]-------------------
local function create(cfg)
    if numRooms == 0 then
        print("ERROR: No rooms detected - check controls")
        return nil
    end
    
    if not Controls.devCams or not Controls.btnCamPreset1 or not controls.txtJSONStorage then
        print("ERROR: Required controls missing (devCams, btnCamPreset1, txtJSONStorage)")
        return nil
    end
    
    if isArr(Controls.txtJSONStorage) then
        print("ERROR: txtJSONStorage must be single control, not array")
        return nil
    end
    
    local ok, ctrl = pcall(function()
        local c = CameraPresetController.new(cfg or {})
        if not c or not c:validateControls() then error("Validation failed") end
        c:registerEvents()
        c:init()
        return c
    end)
    
    if ok and ctrl then
        print(string.format("✅ CameraPresetController initialized - %d rooms, tolerance=%.3f, hold=%.1fs", 
            ctrl.numRooms, ctrl.config.presetTolerance, ctrl.config.holdTime))
        return ctrl
    else
        print("ERROR: Controller creation failed: " .. tostring(ctrl))
        return nil
    end
end

local instance = create({debugging = true})

-- Export
-- luacheck: ignore 431
CameraPresetController = instance

-------------------[ Usage Examples ]-------------------
--[[
-- Manual operations:
CameraPresetController:savePreset(1, 1)      -- Save preset 1 for room 1
CameraPresetController:recallPreset(2, 3)    -- Recall preset 3 for room 2
CameraPresetController:updatePresetMatchLEDs(1)  -- Force LED update
CameraPresetController:saveJSON()            -- Manual JSON save
CameraPresetController:cleanup()             -- Clean up resources

-- Access config:
print("Rooms: " .. CameraPresetController.numRooms)
print("Tolerance: " .. CameraPresetController.config.presetTolerance)
]]--

