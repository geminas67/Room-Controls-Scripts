--[[ 
  Camera Presets Controller - Class-based Implementation
  Author: JHPerkins, Q-SYS (Refactored to Class Structure)
  February, 2025
  Firmware Req: 9.12
  Version: 2.0
  
  Refactored to follow class-based pattern for modularity and reusability
  Maintains all existing camera preset functionality including JSON handling
  Preserves camera position change detection and LED update logic
]]--

-- Required libraries
rapidjson = require("rapidjson")

-- CameraPresetController class
CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

--------** Class Constructor **--------
function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Component storage
    self.components = {
        cameras = {},
        presets = {},
        invalid = {},
        routers = {}  -- New storage for video routers
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        combinedMode = true  -- or false for divided
    }
    
    -- Configuration
    self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        routerOutputs = config and config.routerOutputs or {"select.1"}  -- Default to first output
    }
    
    -- Initialize modules
    self:initJSONModule()
    self:initCameraModule()
    self:initRouterModule()  -- New router module initialization
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** JSON Module **--------
function CameraPresetController:initJSONModule()
    self.jsonModule = {
        save = function()
            local strTemp = rapidjson.encode(self.components.presets, {pretty=true, sort_keys=true})
            if strTemp ~= Controls.txtJSONStorage.String then
                Controls.txtJSONStorage.String = strTemp
                self:debugPrint("JSON data saved")
            else
                self:debugPrint("No new JSON data to save")
            end
        end,
        
        load = function()
            local tblTemp = rapidjson.decode(Controls.txtJSONStorage.String)
            if type(tblTemp) == "table" then
                self.components.presets = tblTemp
                self:debugPrint("JSON data loaded successfully")
            else
                self:debugPrint("JSON data was empty or invalid")
            end
        end
    }
end

--------** Camera Module **--------
function CameraPresetController:initCameraModule()
    self.cameraModule = {
        discoverCameras = function()
            local cameraNames = {}
            for index, tblComponents in pairs(Component.GetComponents()) do
                for k, v in pairs(tblComponents) do
                    if v == "onvif_camera_operative" then
                        table.insert(cameraNames, tblComponents.Name)
                        self.components.cameras[tblComponents.Name] = Component.New(tblComponents.Name)
                        self:debugPrint("Found camera: " .. tblComponents.Name)
                    end
                end
            end
            return cameraNames
        end,
        
        purgeRemovedCameras = function()
            for key, value in pairs(self.components.presets) do
                local found = false
                for k, v in pairs(self.components.cameras) do
                    if key == k then found = true end
                end
                if not found then
                    self.components.presets[key] = nil
                    self:debugPrint("Purged presets for missing camera: " .. key)
                end
            end
        end,
        
        initializePresets = function(cameraNames)
            for _, camName in pairs(cameraNames) do
                if self.components.presets[camName] == nil then
                    self.components.presets[camName] = {}
                    for i, v in ipairs(Controls.btnCamPreset) do
                        self.components.presets[camName][i] = "0 0 0"
                    end
                    self:debugPrint("Initialized presets for camera: " .. camName)
                end
            end
        end,
        
        updatePresetMatchLEDs = function()
            -- Update LEDs for Camera 1
            if Controls.seldevCams01.String ~= "" and self.components.cameras[Controls.seldevCams01.String] then
                local currentPreset = self.components.cameras[Controls.seldevCams01.String]["ptz.preset"].String
                for i, v in ipairs(Controls.ledPresetMatch) do
                    if self.components.presets[Controls.seldevCams01.String] and 
                       self.components.presets[Controls.seldevCams01.String][i] == currentPreset then
                        v.Boolean = true
                    else
                        v.Boolean = false
                    end
                end
            else
                for i, v in ipairs(Controls.ledPresetMatch) do
                    v.Boolean = false
                end
            end

            -- Update LEDs for Camera 2 (if in divided mode)
            if not self.state.combinedMode then
                if Controls.seldevCams02.String ~= "" and self.components.cameras[Controls.seldevCams02.String] then
                    local currentPreset = self.components.cameras[Controls.seldevCams02.String]["ptz.preset"].String
                    for i, v in ipairs(Controls.ledPresetMatch02) do
                        if self.components.presets[Controls.seldevCams02.String] and 
                           self.components.presets[Controls.seldevCams02.String][i] == currentPreset then
                            v.Boolean = true
                        else
                            v.Boolean = false
                        end
                    end
                else
                    for i, v in ipairs(Controls.ledPresetMatch02) do
                        v.Boolean = false
                    end
                end
            end
        end,
        
        savePreset = function(presetIndex)
            local camName = Controls.seldevCams01.String
            if camName ~= "" and self.components.cameras[camName] then
                local oldPreset = self.components.presets[camName][presetIndex]
                local newPreset = self.components.cameras[camName]["ptz.preset"].String
                self.components.presets[camName][presetIndex] = newPreset
                self:debugPrint(string.format("Saved %s Preset[%d] from %s to %s", 
                    camName, presetIndex, oldPreset, newPreset))
                self.jsonModule.save()
            end
        end,
        
        recallPreset = function(presetIndex)
            local camName = Controls.seldevCams01.String
            if camName ~= "" and self.components.cameras[camName] then
                local preset = self.components.presets[camName][presetIndex]
                self.components.cameras[camName]["ptz.preset"].String = preset
                self:debugPrint(string.format("Recalled %s Preset[%d]: %s", 
                    camName, presetIndex, preset))
            end
        end
    }
end

--------** Router Module **--------
function CameraPresetController:initRouterModule()
    self.routerModule = {
        discoverRouters = function()
            for index, tblComponents in pairs(Component.GetComponents()) do
                for k, v in pairs(tblComponents) do
                    if v == "video_router" then
                        self.components.routers[tblComponents.Name] = Component.New(tblComponents.Name)
                        self:debugPrint("Found video router: " .. tblComponents.Name)
                    end
                end
            end
        end,
        
        syncCamChoiceWithRouter = function(router, routerKey, camChoiceControl)
            local selectedRouterName = Controls.compcamRouter.String or "(none)"
            if not router or not router[routerKey] then
                self:debugPrint("Invalid router or router key")
                return
            end
            
            -- Dynamically map router input index to camera name based on current choices
            local camIndexToName = {}
            for i, name in ipairs(camChoiceControl.Choices) do
                camIndexToName[i] = name
            end
            
            -- Event handler updates camChoiceControl based on router state
            router[routerKey].EventHandler = function()
                local routedInputIndex = router[routerKey].Value
                self:debugPrint(string.format("Router %s.%s EventHandler fired, Value=%s", selectedRouterName, routerKey, tostring(routedInputIndex)))
                local cameraName = camIndexToName[routedInputIndex]
                for i = 1, #camChoiceControl.Choices do
                    if camChoiceControl.Choices[i] == cameraName then
                        camChoiceControl.Value = i
                        camChoiceControl.String = cameraName  -- Force UI update
                        self:debugPrint(string.format("Set camChoiceControl.Value = %d (%s), String = %s", i, cameraName, camChoiceControl.String))
                        break
                    end
                end
                self:debugPrint(string.format("After update: camChoiceControl.Value=%s, camChoiceControl.String=%s", tostring(camChoiceControl.Value), tostring(camChoiceControl.String)))
            end
            
            -- Call once at startup
            router[routerKey].EventHandler()
            self:debugPrint(string.format("Synchronized router %s.%s with camera choice", 
                selectedRouterName, routerKey))
        end,
        
        setupRouterSync = function()
            local selectedRouterName = Controls.compcamRouter.String
            local router = self.components.routers[selectedRouterName]
            if router then
                self:debugPrint(string.format("Router sync: routerName=%s, router=%s", tostring(selectedRouterName), tostring(router)))
                -- Sync select.1 with seldevCams01
                self.routerModule.syncCamChoiceWithRouter(router, "select.1", Controls.seldevCams01)
                -- Sync select.2 with seldevCams02
                self.routerModule.syncCamChoiceWithRouter(router, "select.2", Controls.seldevCams02)
            else
                self:debugPrint("No router selected or router not found for sync.")
            end
        end,

        updateRouterOutputs = function(selectedIndex, outputKey)
            local selectedRouterName = Controls.compcamRouter.String
            local router = self.components.routers[selectedRouterName]
            if not router then return end

            if self.state.combinedMode then
                -- In combined mode, update both outputs
                router["select.1"].Value = selectedIndex
                router["select.2"].Value = selectedIndex
            else
                -- In divided mode, only update the specified output
                router[outputKey].Value = selectedIndex
            end
        end
    }
end

--------** Debug Helper **--------
function CameraPresetController:debugPrint(str)
    if self.debugging then
        print("[Camera Presets Debug] " .. str)
    end
end

--------** Event Handler Registration **--------
function CameraPresetController:registerEventHandlers()
    -- Camera selection handlers
    Controls.seldevCams01.EventHandler = function()
        self.cameraModule.updatePresetMatchLEDs()
        -- Update router output 1
        local selectedIndex = Controls.seldevCams01.Value
        self.routerModule.updateRouterOutputs(selectedIndex, "select.1")
    end
    
    Controls.seldevCams02.EventHandler = function()
        self.cameraModule.updatePresetMatchLEDs()
        -- Update router output 2
        local selectedIndex = Controls.seldevCams02.Value
        self.routerModule.updateRouterOutputs(selectedIndex, "select.2")
    end
    
    -- Router selection handler
    Controls.compcamRouter.EventHandler = function()
        self.routerModule.setupRouterSync()
    end

    -- LED On Time knob handler
    Controls.knbledOnTime.EventHandler = function()
        self.config.ledOnTime = Controls.knbledOnTime.Value
        self:debugPrint("LED On Time updated to: " .. self.config.ledOnTime)
    end

    -- Combined Mode handler
    Controls.btnCombinedMode.EventHandler = function()
        self.state.combinedMode = Controls.btnCombinedMode.Boolean
        -- If switching to combined mode, sync output 2 with output 1
        if self.state.combinedMode then
            local selectedIndex = Controls.seldevCams01.Value
            self.routerModule.updateRouterOutputs(selectedIndex, "select.1")
        end
    end
    
    -- Initialize timers and button handlers for each preset
    for i, v in ipairs(Controls.btnCamPreset) do
        self.state.longPressed[i] = false
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Long press detection
        self.state.countdownTimers[i].EventHandler = function()
            self.state.countdownTimers[i]:Stop()
            if Controls.btnCamPreset[i].Boolean then
                self.state.longPressed[i] = true
                Controls.ledPresetSaved[i].Boolean = true
                self.state.ledTimers[i]:Start(self.config.ledOnTime)
            end
        end
        
        -- LED timer completion
        self.state.ledTimers[i].EventHandler = function()
            self.state.ledTimers[i]:Stop()
            Controls.ledPresetSaved[i].Boolean = false
        end
        
        -- Button press/release handler
        v.EventHandler = function(ctl)
            if ctl.Boolean then
                self.state.longPressed[i] = false
                self.state.countdownTimers[i]:Start(self.config.holdTime)
            else
                if self.state.longPressed[i] then
                    self.cameraModule.savePreset(i)
                else
                    self.cameraModule.recallPreset(i)
                end
                self.state.longPressed[i] = false
                self.cameraModule.updatePresetMatchLEDs()
            end
        end
    end
end

--------** Initialization **--------
function CameraPresetController:funcInit()
    -- Load saved presets
    self.jsonModule.load()
    
    -- Discover and initialize cameras and routers
    local cameraNames = self.cameraModule.discoverCameras()
    table.sort(cameraNames)  -- Ensure order is devCam01, devCam02, devCam03
    for i, name in ipairs(cameraNames) do
        self:debugPrint(string.format("Sorted cameraNames[%d]: %s", i, name))
    end
    self.routerModule.discoverRouters()
    self.cameraModule.purgeRemovedCameras()
    self.cameraModule.initializePresets(cameraNames)
    
    -- Set up camera position change handlers
    for _, camName in pairs(cameraNames) do
        self.components.cameras[camName]["ptz.preset"].EventHandler = function()
            self.cameraModule.updatePresetMatchLEDs()
        end
    end
    
    -- Setup router synchronization
    self.routerModule.setupRouterSync()
    
    -- Update UI
    Controls.seldevCams01.Choices = cameraNames
    Controls.seldevCams02.Choices = cameraNames
    Controls.txtJSONStorage.IsDisabled = true
    
    -- Save initial state
    self.jsonModule.save()

    -- Set default router output and camera selection at startup
    for routerName, router in pairs(self.components.routers) do
        if router["select.1"] and router["select.2"] then
            router["select.1"].Value = 1
            router["select.2"].Value = 3
        end
    end
    
    -- After self.routerModule.discoverRouters()
    local routerNames = {}
    for name, _ in pairs(self.components.routers) do
        table.insert(routerNames, name)
    end
    table.sort(routerNames)
    Controls.compcamRouter.Choices = routerNames
    if #routerNames > 0 then
        Controls.compcamRouter.String = routerNames[1]  -- Default to first router
    end
    
    self:debugPrint("Camera Preset Controller Initialized")
end

--------** Cleanup **--------
function CameraPresetController:cleanup()
    -- Stop all timers
    for i, timer in pairs(self.state.countdownTimers) do
        if timer then timer:Stop() end
    end
    for i, timer in pairs(self.state.ledTimers) do
        if timer then timer:Stop() end
    end
    
    -- Clear event handlers
    for _, camera in pairs(self.components.cameras) do
        if camera["ptz.preset"].EventHandler then
            camera["ptz.preset"].EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createCameraPresetController(config)
    local defaultConfig = {
        debugging = true,
        holdTime = Controls.knbHoldTime.Value,
        ledOnTime = Controls.knbledOnTime.Value,
        routerOutputs = {"select.1", "select.2", "select.3"}  -- Default to first three outputs
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return CameraPresetController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created Camera Preset Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main camera preset controller instance
myCameraPresetController = createCameraPresetController()

--------** Usage Examples **--------
--[[
-- Example usage of the camera preset controller:

-- Save a preset manually
myCameraPresetController.cameraModule.savePreset(1)

-- Recall a preset manually
myCameraPresetController.cameraModule.recallPreset(2)

-- Update LED states
myCameraPresetController.cameraModule.updatePresetMatchLEDs()

-- Save JSON data
myCameraPresetController.jsonModule.save()

-- Load JSON data
myCameraPresetController.jsonModule.load()
]]--

function CameraPresetController:updateRouterOutputs(selectedIndex)
    if self.state.combinedMode then
        -- Set all outputs to the selected index
        for _, output in ipairs(self.config.routerOutputs) do
            for routerName, router in pairs(self.components.routers) do
                router[output].Value = selectedIndex
            end
        end
    else
        -- Only set the currently selected output (e.g., select.2)
        -- You may need to track which output is currently active in the UI
        local currentOutput = self.state.activeOutput or "select.1"
        for routerName, router in pairs(self.components.routers) do
            router[currentOutput].Value = selectedIndex
        end
    end
end

function CameraPresetController:setCombinedMode(isCombined)
    self.state.combinedMode = isCombined
end
