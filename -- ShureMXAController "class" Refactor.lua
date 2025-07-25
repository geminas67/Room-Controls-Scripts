--[[ 
  Shure MXA Controls - Robust Class Implementation
  Author: Nikolas Smith, Q-SYS (Emulation & Processor Compatible)
  2025-06-18
  Firmware Req: 10.0.0
  Version: 3.1 - Emulation & Processor Compatible
  
  Optimized for reliability across all Q-SYS environments
  Direct component access, batched operations, robust event handlers
]]--

--------** Class Constructor **--------
ShureMXAController = {}
ShureMXAController.__index = ShureMXAController

function ShureMXAController.new(roomName, config)
    local self = setmetatable({}, ShureMXAController)
    self.roomName = roomName or "Shure MXA"
    self.debugging = (config and config.debugging) or false  -- Disabled by default for performance
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        mxaDevices = "%PLUGIN%_984f65d4-443f-406d-9742-3cb4027ff81c_%FP%_1257aeeea0835196bee126b4dccce889",
        roomControls = (comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls"))
    }
    -- Direct component references for faster access
    self.components = {
        callSync = nil, roomControls = nil,
        mxaDevices = {}, invalid = {}
    }
    
    -- State tracking
    self.state = {
        audioPrivacy = false,
        systemPower = false, 
        fireAlarm = false,
        ledState = false, 
        muteState = false
    }
    
    self.config = {
        ledBrightness = (config and config.ledBrightness) or 5,
        ledOff = (config and config.ledOff) or 0,
        controlColors = { white = 'White', pink = 'Pink', off = 'Off' },
        ledToggleInterval = 1.5
    }
    
    -- Pre-allocate timer for LED toggle
    self.ledToggleTimer = Timer.New()
    self.ledToggleTimer.EventHandler = function()
        self.state.ledState = not self.state.ledState
        self:setAllMXALEDs(self.state.ledState)
    end
    
    return self
end

--------** Debug Helper **--------
function ShureMXAController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." MXA] "..str) end
end

--------** Component Access **--------
function ShureMXAController:setComponentDirect(component, control, value)
    if component and component[control] then
        component[control].Value = value
        return true
    end
    return false
end

function ShureMXAController:setComponentBoolean(component, control, value)
    if component and component[control] then
        component[control].Boolean = value
        return true
    end
    return false
end

function ShureMXAController:triggerComponent(component, control)
    if component and component[control] then
        component[control]:Trigger()
        return true
    end
    return false
end

--------** Batched MXA Operations **--------
function ShureMXAController:setAllMXALEDs(state)
    local value = state and self.config.ledBrightness or self.config.ledOff
    for _, device in pairs(self.components.mxaDevices) do
        if device and device.bright then
            device.bright.Value = value
        end
    end
end

function ShureMXAController:setAllMXAMute(state)
    self.state.muteState = state
    for _, device in pairs(self.components.mxaDevices) do
        if device and device.muteall then
            device.muteall.Boolean = state
        end
    end
end

function ShureMXAController:getMXADeviceCount()
    local count = 0
    for _, device in pairs(self.components.mxaDevices) do 
        if device then count = count + 1 end 
    end
    return count
end

--------** Privacy Control **--------
function ShureMXAController:setAudioPrivacy(state)
    self.state.audioPrivacy = state
    self:setAllMXAMute(state)
    if self.debugging then self:debugPrint("Audio Privacy: "..tostring(state)) end
end

function ShureMXAController:getPrivacyState()
    return self.state.audioPrivacy
end

--------** System Control **--------
function ShureMXAController:setSystemPower(state)
    self.state.systemPower = state
    if not state then
        self:setAllMXAMute(true)
        self:setAllMXALEDs(false)
        if self.debugging then self:debugPrint("System Power Off") end
    else
        if self.debugging then self:debugPrint("System Power On") end
    end
end

function ShureMXAController:setFireAlarm(state)
    self.state.fireAlarm = state
    if state then
        if self.debugging then self:debugPrint("Fire Alarm Active") end
        self.ledToggleTimer:Start(self.config.ledToggleInterval)
        self:setAllMXAMute(true)
        self:setAllMXALEDs(false)
    else
        self.ledToggleTimer:Stop()
        if self.components.callSync and self.components.callSync["off.hook"] then
            local isOffHook = self.components.callSync["off.hook"].Boolean
            if isOffHook then
                if self.debugging then self:debugPrint("Fire Alarm Cleared - Call Off-Hook") end
                self:setAllMXAMute(false)
                self:setAllMXALEDs(true)
            else
                if self.debugging then self:debugPrint("Fire Alarm Cleared - Call On-Hook") end
                self:setAllMXAMute(true)
                self:setAllMXALEDs(false)
            end
        end
    end
end

--------** Call Sync Control **--------
function ShureMXAController:setHookState(state)
    if self.debugging then self:debugPrint("Call Sync Hook: "..tostring(state)) end
    self:setAllMXALEDs(state)
end

function ShureMXAController:setCallMuteState(state)
    if self.debugging then self:debugPrint("Call Sync Mute: "..tostring(state)) end
    self:setAllMXAMute(state)
end

function ShureMXAController:endCall()
    if self.components.callSync then
        self:triggerComponent(self.components.callSync, "end.call")
        if self.debugging then self:debugPrint("End call triggered") end
    end
end

--------** Component Management **--------
function ShureMXAController:setComponent(ctrl, componentType)
    if not ctrl then
        if self.debugging then self:debugPrint("Control is nil for: " .. componentType) end
        return nil
    end
    
    local componentName = ctrl.String
    
    if componentName == "" then
        self:setComponentValid(componentType)
        ctrl.Color = "white"
        return nil
    elseif componentName == self.clearString then
        ctrl.String = ""
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = self.config.controlColors.pink
        self:setComponentInvalid(componentType)
        return nil
    else
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
end

function ShureMXAController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:updateStatus()
end

function ShureMXAController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:updateStatus()
end

function ShureMXAController:updateStatus()
    if Controls.txtStatus then
        for _, v in pairs(self.components.invalid) do
            if v == true then
                Controls.txtStatus.String = "Invalid Components"
                Controls.txtStatus.Value = 1
                return
            end
        end
        Controls.txtStatus.String = "OK"
        Controls.txtStatus.Value = 0
    end
end

--------** Component Setup **--------
function ShureMXAController:setupComponents()
    -- Setup main components using global Controls table
    if Controls.compCallSync then
        self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
    end
    
    if Controls.compRoomControls then
        self.components.roomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    end
    
    -- Setup MXA devices using global Controls table
    if Controls.devMXAs then
        for i, _ in ipairs(Controls.devMXAs) do
            self.components.mxaDevices[i] = self:setComponent(Controls.devMXAs[i], "MXA [" .. i .. "]")
        end
    end
end

--------** Event Handlers **--------
function ShureMXAController:registerCallSyncEventHandlers()
    local callSync = self.components.callSync
    if not callSync then return end
    
    local offHook = callSync["off.hook"]
    if offHook then
        offHook.EventHandler = function(ctl) self:setHookState(ctl.Boolean) end
    end
    
    local mute = callSync["mute"]
    if mute then
        mute.EventHandler = function(ctl) self:setCallMuteState(ctl.Boolean) end
    end
end

function ShureMXAController:registerRoomControlsEventHandlers()
    local roomControls = self.components.roomControls
    if not roomControls then return end
    
    local systemPower = roomControls["ledSystemPower"]
    if systemPower then
        systemPower.EventHandler = function(ctl) self:setSystemPower(ctl.Boolean) end
    end
    
    local fireAlarm = roomControls["ledFireAlarm"]
    if fireAlarm then
        fireAlarm.EventHandler = function(ctl) self:setFireAlarm(ctl.Boolean) end
    end
end

function ShureMXAController:registerMXAEventHandlers(idx)
    local device = self.components.mxaDevices[idx]
    if not device then return end
    
    local muteAll = device["muteall"]
    if muteAll then
        muteAll.EventHandler = function(control) 
            if self.debugging then self:debugPrint("MXA ["..idx.."] Mute: "..tostring(control.Boolean)) end 
        end
    end
    
    local bright = device["bright"]
    if bright then
        bright.EventHandler = function(control) 
            if self.debugging then self:debugPrint("MXA ["..idx.."] Brightness: "..tostring(control.Value)) end 
        end
    end
end

function ShureMXAController:registerEventHandlers()
    -- Direct button handler using global Controls table
    if Controls.btnMXAMute then
        Controls.btnMXAMute.EventHandler = function(ctl) 
            self:setAllMXAMute(ctl.Boolean) 
        end
    end

    -- Component change handlers using global Controls table
    if Controls.compRoomControls then
        Controls.compRoomControls.EventHandler = function() 
            self.components.roomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
            if self.components.roomControls then 
                self:registerRoomControlsEventHandlers() 
            end
        end
    end

    if Controls.compCallSync then
        Controls.compCallSync.EventHandler = function() 
            self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
            if self.components.callSync then  
                self:registerCallSyncEventHandlers()   
            end
        end
    end

    -- MXA device handlers using global Controls table
    if Controls.devMXAs then
        for i, _ in ipairs(Controls.devMXAs) do
            Controls.devMXAs[i].EventHandler = function() 
                self.components.mxaDevices[i] = self:setComponent(Controls.devMXAs[i], "MXA [" .. i .. "]")
                if self.components.mxaDevices[i] then 
                    self:registerMXAEventHandlers(i) 
                end
            end
        end
    end
end

--------** Component Discovery **--------
function ShureMXAController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {}, 
        CallSyncNames = {},
        MXANames = {}
    }

    -- Single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == self.componentTypes.mxaDevices then
            table.insert(namesTable.MXANames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    -- Sort and add clear option in single pass
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    -- Direct assignment to controls using global Controls table
    if Controls.compRoomControls then 
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames 
    end
    
    if Controls.compCallSync then 
        Controls.compCallSync.Choices = namesTable.CallSyncNames 
    end
    
    --   MXA device handlers using global Controls table
    if Controls.devMXAs then
        for i, _ in ipairs(Controls.devMXAs) do
            Controls.devMXAs[i].Choices = namesTable.MXANames
        end
    end
end

--------** System Initialization **--------
function ShureMXAController:performSystemInitialization()
    if self.debugging then self:debugPrint("System initialization") end
    self:setAllMXAMute(true)
    self:setAllMXALEDs(false)
    if self.debugging then self:debugPrint("System initialization completed") end
end

--------** Initialization **--------
function ShureMXAController:funcInit()
    if self.debugging then self:debugPrint("Starting initialization...") end
    
    -- Use global Controls table directly - no caching
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    if self.debugging then 
        self:debugPrint("Initialized with "..self:getMXADeviceCount().." MXA devices") 
    end
end

--------** Cleanup **--------
function ShureMXAController:cleanup()
    -- Stop timer first
    self.ledToggleTimer:Stop()
    
    -- Clear event handlers directly
    if self.components.callSync then
        if self.components.callSync["off.hook"] then 
            self.components.callSync["off.hook"].EventHandler = nil 
        end
        if self.components.callSync["mute"] then 
            self.components.callSync["mute"].EventHandler = nil 
        end
    end
    
    if self.components.roomControls then
        if self.components.roomControls["ledSystemPower"] then self.components.roomControls["ledSystemPower"].EventHandler = nil end
        if self.components.roomControls["ledFireAlarm"] then self.components.roomControls["ledFireAlarm"].EventHandler = nil end
    end
    
    for _, device in pairs(self.components.mxaDevices) do
        if device then
            if device["muteall"] then 
                device["muteall"].EventHandler = nil 
            end
            if device["bright"] then 
                device["bright"].EventHandler = nil 
            end
            if device["mute"] then 
                device["mute"].EventHandler = nil 
            end
        end
    end
    
    -- Reset component references
    self.components = {
        callSync = nil, 
        roomControls = nil,
        mxaDevices = {}, 
        invalid = {}
    }
    if self.debugging then self:debugPrint("Cleanup completed") end
end

--------** Factory Function **--------
local function createShureMXAController(roomName, config)
    print("Creating Shure MXA Controller for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = ShureMXAController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    
    if success then
        print("Successfully created Shure MXA Controller for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
local formattedRoomName = "[Shure MXA Controller]"
myMXAController = createShureMXAController(formattedRoomName)

if myMXAController then
    print("Shure MXA Controller created successfully!")
else
    print("ERROR: Failed to create Shure MXA Controller!")
end

--------** Usage Examples **--------
--[[

-- Direct MXA control (fastest path)
myMXAController:setAllMXAMute(true)
myMXAController:setAllMXALEDs(true)

-- Privacy control
myMXAController:setAudioPrivacy(true)

-- System control
myMXAController:setSystemPower(false)
myMXAController:setFireAlarm(true)

-- Call control
myMXAController:endCall()

-- Status queries
local deviceCount = myMXAController:getMXADeviceCount()
local privacyState = myMXAController:getPrivacyState()
]]--

