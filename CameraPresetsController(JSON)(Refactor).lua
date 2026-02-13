--[[
  Camera Preset Controller - Q-SYS Control Script
  Single Room Implementation
  Author: Nikolas Smith, Q-SYS
  Version: 6.0 (Refactored - Event-Driven, Lean Architecture)
  Firmware Req: 10.0.0
  
  Features: Camera/preset management, JSON sync, router integration
]]--

-- luacheck: globals Controls Timer Component rapidjson

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
    compRoomControls = Controls.compRoomControls,
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
    videoRouter = "video_router",
    roomControls = "device_controller_script"
}

rapidjson = require("rapidjson")

-------------------[ Utilities ]-------------------
local function isArr(tbl)
    return type(tbl) == "table" and #tbl > 0
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
    
    -- Merge config
    self.config = {}
    for key, value in pairs(config) do
        self.config[key] = (userConfig and userConfig[key]) or value
    end
    
    -- Components storage
    self.components = {
        cameras = {},
        presets = {},
        routers = {},
        roomControls = {}
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        debounceTimer = Timer.New(),
        currentRouter = nil,
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
    
    controls.txtJSONStorage.String = json
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

-------------------[ Camera Methods ]-------------------
function CameraPresetController:discoverCameras()
    self.components.cameras = {}
    
    local names = {}
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then
        self:error("Component discovery failed")
        return names
    end
    
    for _, comp in pairs(comps) do
        if comp.Type == componentTypes.camera and comp.Name then
            if validateComponent(comp.Name) then
                table.insert(names, comp.Name)
                self.components.cameras[comp.Name] = Component.New(comp.Name)
                self:debugPrint("Camera found: " .. comp.Name)
            end
        end
    end
    
    table.sort(names)
    return names
end

function CameraPresetController:initPresets()
    local names = {}
    for cameraName, _ in pairs(self.components.cameras) do table.insert(names, cameraName) end
    if #names == 0 then return end
    
    local btnArr = isArr(controls.btnCamPreset) and controls.btnCamPreset or {controls.btnCamPreset}
    local numPresets = #btnArr
    if numPresets == 0 then return end
    
    for _, camName in pairs(names) do
        if not self.components.presets[camName] then
            self.components.presets[camName] = {}
            for i = 1, numPresets do
                self.components.presets[camName][i] = "0 0 0"
            end
            self:debugPrint("Presets initialized for " .. camName)
        end
    end
end

function CameraPresetController:updatePresetMatchLEDs()
    self.state.debounceTimer:Stop()
    self.state.debounceTimer.EventHandler = function() self:_updateLEDsInternal() end
    self.state.debounceTimer:Start(self.config.debounceDelay)
end

function CameraPresetController:_updateLEDsInternal()
    local clearLEDs = function()
        local leds = isArr(controls.ledPresetMatch) and controls.ledPresetMatch or {controls.ledPresetMatch}
        for _, led in ipairs(leds) do setProp(led, "Boolean", false) end
    end
    
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then clearLEDs(); return end
    
    local cam = self.components.cameras[camName]
    if not cam then clearLEDs(); return end
    
    -- Skip if moving
    if cam["is.moving"] and cam["is.moving"].Boolean then clearLEDs(); return end
    
    local current = cam["ptz.preset"] and cam["ptz.preset"].String or ""
    if current == "" or type(current) ~= "string" or current:match("^%s*$") then
        local now = os.clock()
        if not self.state.lastEmptyPresetLog or (now - self.state.lastEmptyPresetLog) > 5 then
            self:debugPrint("No preset data for " .. camName)
            self.state.lastEmptyPresetLog = now
        end
        clearLEDs()
        return
    end
    
    local saved = self.components.presets[camName] or {}
    local leds = isArr(controls.ledPresetMatch) and controls.ledPresetMatch or {controls.ledPresetMatch}
    
    for i, led in ipairs(leds) do
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
    
    return math.abs(currentPan - savedPan) <= tolerance and 
           math.abs(currentTilt - savedTilt) <= tolerance and 
           math.abs(currentZoom - savedZoom) <= tolerance
end

function CameraPresetController:savePreset(presetIdx)
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then
        self:error("No camera selected")
        return false
    end
    
    local cam = self.components.cameras[camName]
    if not cam or not cam["ptz.preset"] then
        self:error("Invalid camera: " .. camName)
        return false
    end
    
    local currentPreset = cam["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        self:error("No preset data for " .. camName)
        return false
    end
    
    if not self.components.presets[camName] then
        self.components.presets[camName] = {}
    end
    
    local oldPreset = self.components.presets[camName][presetIdx] or "not set"
    self.components.presets[camName][presetIdx] = currentPreset
    self:debugPrint(string.format("Saved %s Preset[%d]: %s (was: %s)", 
        camName, presetIdx, currentPreset, oldPreset))
    
    if not self:saveJSON() then
        self:error("JSON save failed")
    end
    
    return true
end

function CameraPresetController:recallPreset(presetIdx)
    local camName = controls.devCams and controls.devCams.String or ""
    if camName == "" then return false end
    
    local cam = self.components.cameras[camName]
    if not cam or not cam["ptz.preset"] then return false end
    
    local saved = self.components.presets[camName]
    if not saved or not saved[presetIdx] or saved[presetIdx] == "0 0 0" then
        self:error(string.format("Preset[%d] not saved for %s", presetIdx, camName))
        return false
    end
    
    cam["ptz.preset"].String = saved[presetIdx]
    self:debugPrint(string.format("Recalled %s Preset[%d]: %s", camName, presetIdx, saved[presetIdx]))
    return true
end

-------------------[ Router Methods ]-------------------
function CameraPresetController:discoverRouters()
    self.components.routers = {}
    
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then return end
    
    for _, comp in pairs(comps) do
        if comp.Type and comp.Type:match(componentTypes.videoRouter) and comp.Name then
            if validateComponent(comp.Name) then
                self.components.routers[comp.Name] = Component.New(comp.Name)
                self:debugPrint("Router found: " .. comp.Name)
            end
        end
    end
end

function CameraPresetController:discoverRoomControls()
    self.components.roomControls = {}
    
    local ok, comps = pcall(Component.GetComponents)
    if not ok or not comps then return end
    
    for _, comp in pairs(comps) do
        if comp.Type == componentTypes.roomControls and comp.Name then
            if comp.Name:match("^compRoomControls") and validateComponent(comp.Name) then
                self.components.roomControls[comp.Name] = Component.New(comp.Name)
                self:debugPrint("Room controls found: " .. comp.Name)
            end
        end
    end
end

function CameraPresetController:setupRouterSync()
    if not controls.compcamRouter then return false end
    
    local routerName = controls.compcamRouter.String
    if not routerName or routerName == "" then return false end
    
    -- Cleanup old handlers
    if self.state.currentRouter then
        local oldOutKey = controls.routerOutput and controls.routerOutput.String or "select.1"
        cleanupHandlers(self.state.currentRouter, {oldOutKey})
    end
    
    local router = self.components.routers[routerName]
    if not router then
        self:error("Router not found: " .. routerName)
        return false
    end
    
    self.state.currentRouter = router
    
    local outKey = controls.routerOutput and controls.routerOutput.String ~= "" 
        and controls.routerOutput.String or "select.1"
    
    if not router[outKey] then
        self:error("Router output not found: " .. outKey)
        return false
    end
    
    if not controls.devCams then return false end
    
    return self:syncCamWithRouter(router, outKey, controls.devCams)
end

function CameraPresetController:syncCamWithRouter(router, key, camCtrl)
    if not router or not router[key] or not camCtrl then return false end
    
    -- luacheck: ignore 122
    router[key].EventHandler = function()
        local idx = router[key].Value
        
        if not camCtrl.Choices then return end
        
        if idx and idx > 0 and idx <= #camCtrl.Choices then
            if setProp(camCtrl, "Value", idx) then
                camCtrl.String = camCtrl.Choices[idx]
                self:debugPrint("Router sync: " .. key .. " → " .. camCtrl.String)
            end
            self:updatePresetMatchLEDs()
        end
    end
    
    if router[key].EventHandler then
        router[key].EventHandler()
        self:debugPrint("Router output " .. key .. " handler registered")
        return true
    end
    
    return false
end

-------------------[ Control Validation ]-------------------
function CameraPresetController:validateControls()
    if not Controls.devCams then
        self:error("devCams control missing")
        return false
    end
    
    if not Controls.btnCamPreset then
        self:error("btnCamPreset control missing")
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
    
    if isArr(controls.devCams) then
        self:error("devCams must be single control, not array")
        return false
    end
    
    self:debugPrint("Control validation passed")
    return true
end

-------------------[ Initialization ]-------------------
function CameraPresetController:init()
    if self.state.initialized then return end
    
    self:debugPrint("=== Initialization Started ===")
    self:debugPrint(string.format("Config: debugging=%s, tolerance=%.3f, hold=%.1fs, led=%.1fs", 
        tostring(self.debugging), self.config.presetTolerance, 
        self.config.holdTime, self.config.ledOnTime))
    
    -- Load JSON
    if not self:loadJSON() then
        self:debugPrint("No existing JSON - will create new preset structure")
    end
    
    local cams = self:discoverCameras()
    if #cams == 0 then
        self:error("No cameras found")
        setProp(controls.txtStatus, "String", "No Cameras Found")
        setProp(controls.txtStatus, "Value", 2)
        return
    end
    
    for i, name in ipairs(cams) do
        self:debugPrint(string.format("Camera[%d]: %s", i, name))
    end
    
    self:discoverRouters()
    self:discoverRoomControls()
    self:initPresets()
    self:setupCameraMonitoring(cams)
    self:setupCameraChoices(cams)
    self:updateRouterChoices()
    self:updateRouterOutputChoices()
    self:setupRouterSync()
    self:updatePresetMatchLEDs()
    
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
    
    self.state.initialized = true
    self:debugPrint("=== Initialization Complete ===")
end

-------------------[ Event Registration ]-------------------
function CameraPresetController:registerEvents()
    self:debugPrint("Registering event handlers...")
    
    -- Camera selection
    if controls.devCams then
        bind(controls.devCams, function()
            self:updatePresetMatchLEDs()
        end)
        self:debugPrint("Registered camera selection handler")
    end
    
    -- Router selector
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            self:updateRouterOutputChoices()
            self:setupRouterSync()
        end)
        self:debugPrint("Registered router selector handler")
    end
    
    -- Router output
    if controls.routerOutput then
        bind(controls.routerOutput, function()
            self:setupRouterSync()
        end)
        self:debugPrint("Registered router output handler")
    end
    
    -- Config knobs
    if controls.knbledOnTime then
        bind(controls.knbledOnTime, function()
            local val = controls.knbledOnTime.Value
            if val and val > 0 then
                self.config.ledOnTime = val
                self:debugPrint("LED On Time: " .. val)
            end
        end)
    end
    
    if controls.knbHoldTime then
        bind(controls.knbHoldTime, function()
            local val = controls.knbHoldTime.Value
            if val and val > 0 then
                self.config.holdTime = val
                self:debugPrint("Hold Time: " .. val)
            end
        end)
    end
    
    self:initPresetButtons()
end

function CameraPresetController:initPresetButtons()
    if not controls.btnCamPreset then return end
    
    local btns = isArr(controls.btnCamPreset) and controls.btnCamPreset or {controls.btnCamPreset}
    
    for presetIdx, btn in ipairs(btns) do
        if btn then
            self.state.longPressed[presetIdx] = false
            self.state.countdownTimers[presetIdx] = Timer.New()
            self.state.ledTimers[presetIdx] = Timer.New()
            
            -- Long press timer
            -- luacheck: ignore 122
            self.state.countdownTimers[presetIdx].EventHandler = function()
                self.state.countdownTimers[presetIdx]:Stop()
                if btns[presetIdx] and btns[presetIdx].Boolean then
                    self.state.longPressed[presetIdx] = true
                    self:handleSave(presetIdx)
                end
            end
            
            -- LED flash timer
            -- luacheck: ignore 122
            self.state.ledTimers[presetIdx].EventHandler = function()
                self.state.ledTimers[presetIdx]:Stop()
                local leds = isArr(controls.ledPresetSaved) and controls.ledPresetSaved or {controls.ledPresetSaved}
                if leds[presetIdx] then setProp(leds[presetIdx], "Boolean", false) end
            end
            
            -- Button handler
            bind(btn, function()
                if btns[presetIdx].Boolean then
                    self.state.longPressed[presetIdx] = false
                    self.state.countdownTimers[presetIdx]:Start(self.config.holdTime)
                else
                    self.state.countdownTimers[presetIdx]:Stop()
                    if not self.state.longPressed[presetIdx] then
                        self:handleRecall(presetIdx)
                    end
                end
            end)
        end
    end
    
    self:debugPrint(string.format("Registered %d preset button handlers", #btns))
end

function CameraPresetController:handleSave(presetIdx)
    if not self:savePreset(presetIdx) then return end
    
    -- Flash LED
    local leds = isArr(controls.ledPresetSaved) and controls.ledPresetSaved or {controls.ledPresetSaved}
    if leds[presetIdx] then
        setProp(leds[presetIdx], "Boolean", true)
        self.state.ledTimers[presetIdx]:Start(self.config.ledOnTime)
    end
    
    self:updatePresetMatchLEDs()
end

function CameraPresetController:handleRecall(presetIdx)
    if not self:recallPreset(presetIdx) then return end
    self:updatePresetMatchLEDs()
end

function CameraPresetController:setupCameraMonitoring(camNames)
    for _, name in pairs(camNames) do
        local cam = self.components.cameras[name]
        if cam then
            if cam["ptz.preset"] then
                bind(cam["ptz.preset"], function() self:updatePresetMatchLEDs() end)
                self:debugPrint("Monitoring position: " .. name)
            end
            if cam["is.moving"] then
                bind(cam["is.moving"], function() self:updatePresetMatchLEDs() end)
                self:debugPrint("Monitoring movement: " .. name)
            end
        end
    end
end

function CameraPresetController:setupCameraChoices(camNames)
    if not controls.devCams then return end
    
    setProp(controls.devCams, "Choices", camNames)
    self:debugPrint(string.format("Camera choices: %d available", #camNames))
    
    if controls.txtJSONStorage then
        controls.txtJSONStorage.IsDisabled = true
    end
    
    -- Set default
    if #camNames > 0 then
        local defaultSet = false
        for i, name in ipairs(camNames) do
            if name == self.config.defaultCamera then
                controls.devCams.String = name
                controls.devCams.Value = i
                defaultSet = true
                break
            end
        end
        
        if not defaultSet then
            controls.devCams.String = camNames[1]
            controls.devCams.Value = 1
        end
        
        self:debugPrint("Default camera: " .. controls.devCams.String)
        self:recallDefaultPreset()
    end
end

function CameraPresetController:recallDefaultPreset()
    local cam = controls.devCams and controls.devCams.String or ""
    if cam == "" then return end
    
    if self:recallPreset(self.config.defaultPreset) then
        self:debugPrint(string.format("Default preset %d recalled for %s", 
            self.config.defaultPreset, cam))
    end
end

function CameraPresetController:updateRouterChoices()
    if not controls.compcamRouter then return end
    
    local names = {}
    for name, _ in pairs(self.components.routers) do
        table.insert(names, name)
    end
    table.sort(names)
    table.insert(names, self.clearString)
    
    controls.compcamRouter.Choices = names
    if #names > 0 then
        controls.compcamRouter.String = names[1]
        self:debugPrint(string.format("Router choices updated: %d available", #names - 1))
    end
end

function CameraPresetController:updateRouterOutputChoices()
    if not controls.routerOutput or not controls.compcamRouter then return end
    
    local function clearOutputs()
        controls.routerOutput.Choices = {}
        controls.routerOutput.String = ""
    end
    
    local routerName = controls.compcamRouter.String
    if not routerName or routerName == "" or routerName == self.clearString then
        clearOutputs()
        return
    end
    
    local router = self.components.routers[routerName]
    if not router then
        clearOutputs()
        return
    end
    
    local outputNames = {}
    for controlName, _ in pairs(router) do
        if type(controlName) == "string" and controlName:match("^select%.%d+$") then
            table.insert(outputNames, controlName)
        end
    end
    
    table.sort(outputNames, function(a, b)
        return tonumber(a:match("%.(%d+)$")) < tonumber(b:match("%.(%d+)$"))
    end)
    
    if #outputNames > 0 then
        setProp(controls.routerOutput, "Choices", outputNames)
        
        local currentOutput = controls.routerOutput.String
        local found = false
        for _, outputName in ipairs(outputNames) do
            if outputName == currentOutput then found = true; break end
        end
        if not found then
            controls.routerOutput.String = outputNames[1]
        end
        
        self:debugPrint(string.format("Router output choices: %d available", #outputNames))
    else
        controls.routerOutput.Choices = {"select.1"}
        controls.routerOutput.String = "select.1"
    end
end

-------------------[ Cleanup ]-------------------
function CameraPresetController:cleanup()
    self:debugPrint("=== Cleanup Started ===")
    
    -- Stop timers
    for _, timer in pairs(self.state.countdownTimers) do if timer then timer:Stop() end end
    for _, timer in pairs(self.state.ledTimers) do if timer then timer:Stop() end end
    if self.state.debounceTimer then self.state.debounceTimer:Stop() end
    
    -- Clear handlers
    for _, cam in pairs(self.components.cameras) do
        if cam then
            if cam["ptz.preset"] then cam["ptz.preset"].EventHandler = nil end
            if cam["is.moving"] then cam["is.moving"].EventHandler = nil end
        end
    end
    
    self.state.initialized = false
    self:debugPrint("=== Cleanup Complete ===")
end

-------------------[ Factory & Initialization ]-------------------
local function create(cfg)
    if not Controls.devCams or not Controls.btnCamPreset or not controls.txtJSONStorage then
        print("ERROR: Required controls missing (devCams, btnCamPreset, txtJSONStorage)")
        return nil
    end
    
    if isArr(Controls.devCams) then
        print("ERROR: devCams must be single control, not array")
        return nil
    end
    
    if isArr(Controls.txtJSONStorage) then
        print("ERROR: txtJSONStorage must be single control, not array")
        return nil
    end
    
    local ok, ctrl = pcall(function()
        local controller = CameraPresetController.new(cfg or {})
        if not controller or not controller:validateControls() then error("Validation failed") end
        controller:registerEvents()
        controller:init()
        return controller
    end)
    
    if ok and ctrl then
        print(string.format("✅ CameraPresetController initialized - tolerance=%.3f, hold=%.1fs", 
            ctrl.config.presetTolerance, ctrl.config.holdTime))
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
CameraPresetController:savePreset(1)        -- Save preset 1
CameraPresetController:recallPreset(2)      -- Recall preset 2
CameraPresetController:updatePresetMatchLEDs()  -- Force LED update
CameraPresetController:saveJSON()           -- Manual JSON save
CameraPresetController:cleanup()            -- Clean up resources

-- Access config:
print("Tolerance: " .. CameraPresetController.config.presetTolerance)
]]--
