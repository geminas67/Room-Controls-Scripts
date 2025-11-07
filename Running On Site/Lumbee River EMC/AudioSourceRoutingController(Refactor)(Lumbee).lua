--[[
    Audio Source Routing Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-11-07
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt specifications (event-driven, OOP modular)
    - Manages audio source routing for divisible space (Rm-A, Rm-B, Combined EMC TR)
    - All event registration is DRY and centralized using control/event maps
    - Configuration-driven routing logic eliminates repetitive switch statements
    - Early returns and guard clauses for flattened control flow
]]

-------------------[ Component References ]-------------------
local components = {
    initTrigger = Component.New('SYS - Initialize Trigger'),
    emcUCISelector = Component.New('EMC TR UCI Layer Selector'),
    rmAUCISelector = Component.New('Rm-A-UCI Layer Selector'),
    rmBUCISelector = Component.New('Rm-B-UCI Layer Selector'),
    rmBPowerState = Component.New(' Rm-B Power State_SEL'),
    rmAPowerState = Component.New(' Rm-A Power State_SEL'),
    rmBMixer = Component.New('Rm-B PGM-Mixer'),
    rmAMixer = Component.New('Rm-A PGM-Mixer'),
    combinerSS = Component.New('EMC_TR_Combiner_SS'),
    rmAStatusBar = Component.New('Rm-A Status Bar'),
    displayControlsA = Component.New('compDisplayControlsRoomA'),
    rmBStatusBar = Component.New('Rm-B Status Bar'),
    displayControlsB = Component.New('compDisplayControlsRoomB')
}

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function validateComponents()
    local required = {
        'emcUCISelector', 'rmAUCISelector', 'rmBUCISelector',
        'rmAPowerState', 'rmBPowerState',
        'rmAMixer', 'rmBMixer', 'combinerSS'
    }
    
    local missing = {}
    for _, name in ipairs(required) do
        if not components[name] then 
            table.insert(missing, name) 
        end
    end
    
    if #missing > 0 then
        print("ERROR: AudioSourceRoutingController missing required components:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end
    
    return true
end

-------------------[ Base Module Class ]-------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    return self
end

function BaseModule:debug(msg)
    if self.controller and self.controller.debugging then
        self.controller:debugPrint("[" .. self.name .. "] " .. msg)
    end
end

-------------------[ Audio Routing Module ]-------------------
local AudioRoutingModule = setmetatable({}, BaseModule)
AudioRoutingModule.__index = AudioRoutingModule

function AudioRoutingModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "AudioRouting"), AudioRoutingModule)
    
    -- Configuration-driven routing maps for DRY pattern
    self.mixerChannelMap = {
        Laptop = { channels = {1, 4}, delay = 0.2 },
        PC = { channels = {3, 5}, delay = 0.2 },
        WPres = { channels = {2}, delay = 0.2 }
    }
    
    -- Display button mappings for each source
    self.displayButtonMap = {
        RmA_Laptop = { roomA = 9, roomB = nil },
        RmA_PC = { roomA = 7, roomB = nil },
        RmA_WPres = { roomA = 5, roomB = nil },
        RmB_Laptop = { roomA = nil, roomB = 10 },
        RmB_PC = { roomA = nil, roomB = 8 },
        RmB_WPres = { roomA = nil, roomB = 6 },
        Combined_RmA_Laptop = { roomA = 9, roomB = 9 },
        Combined_RmA_PC = { roomA = 7, roomB = 7 },
        Combined_RmB_Laptop = { roomA = 10, roomB = 10 },
        Combined_RmB_PC = { roomA = 8, roomB = 8 },
        Combined_RmA_WPres = { roomA = 5, roomB = 5 },
        Combined_RmB_WPres = { roomA = 6, roomB = 6 }
    }
    
    return self
end

function AudioRoutingModule:muteAllChannels(mixer)
    if not mixer then return end
    
    for i = 1, 5 do
        setProp(mixer['input_' .. i .. '_mute'], "Boolean", true)
    end
    self:debug("Muted all channels on " .. (mixer == components.rmAMixer and "Room A" or "Room B") .. " mixer")
end

function AudioRoutingModule:muteAllRooms()
    self:muteAllChannels(components.rmAMixer)
    self:muteAllChannels(components.rmBMixer)
    self:debug("Muted all channels in both rooms")
end

function AudioRoutingModule:unmuteChannels(mixer, sourceType)
    if not mixer or not sourceType then return end
    
    local config = self.mixerChannelMap[sourceType]
    if not config then
        self:debug("Invalid source type: " .. tostring(sourceType))
        return
    end
    
    -- Mute all channels first
    self:muteAllChannels(mixer)
    
    -- Unmute specified channels after delay
    Timer.CallAfter(function()
        for _, channel in ipairs(config.channels) do
            setProp(mixer['input_' .. channel .. '_mute'], "Boolean", false)
        end
        self:debug("Unmuted channels " .. table.concat(config.channels, ", ") .. " on mixer")
    end, config.delay)
end

function AudioRoutingModule:routeAudio(room, sourceType)
    local mixer = (room == "RmA") and components.rmAMixer or 
                  (room == "RmB") and components.rmBMixer or nil
    
    if not mixer then
        self:debug("Invalid room: " .. tostring(room))
        return
    end
    
    self:unmuteChannels(mixer, sourceType)
    self:debug("Routed audio: " .. room .. " -> " .. sourceType)
end

function AudioRoutingModule:routeCombinedAudio(sourceRoom, sourceType)
    -- For combined mode, route to both mixers but only unmute the source room's channels
    local sourceMixer = (sourceRoom == "RmA") and components.rmAMixer or components.rmBMixer
    
    -- Mute all channels in both rooms first
    self:muteAllRooms()
    
    -- Unmute only the source room's channels
    Timer.CallAfter(function()
        local config = self.mixerChannelMap[sourceType]
        if config then
            for _, channel in ipairs(config.channels) do
                setProp(sourceMixer['input_' .. channel .. '_mute'], "Boolean", false)
            end
        end
    end, 0.2)
    
    self:debug("Routed combined audio: " .. sourceRoom .. " -> " .. sourceType)
end

function AudioRoutingModule:triggerDisplayButton(buttonConfig)
    if not buttonConfig then return end
    
    if buttonConfig.roomA and components.displayControlsA then
        setProp(components.displayControlsA['btnSource ' .. buttonConfig.roomA], "Boolean", true)
    end
    
    if buttonConfig.roomB and components.displayControlsB then
        setProp(components.displayControlsB['btnSource ' .. buttonConfig.roomB], "Boolean", true)
    end
end

-------------------[ State Management Module ]-------------------
local StateModule = setmetatable({}, BaseModule)
StateModule.__index = StateModule

function StateModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "State"), StateModule)
    return self
end

function StateModule:isCombined()
    return components.combinerSS and components.combinerSS['load_2'].Boolean
end

function StateModule:isRoomDivided()
    return components.combinerSS and components.combinerSS['load_1'].Boolean
end

function StateModule:isRoomReady(room)
    if room == "RmA" then
        return components.rmAStatusBar and components.rmAStatusBar['percent_1'].String == '100%'
    elseif room == "RmB" then
        return components.rmBStatusBar and components.rmBStatusBar['percent_1'].String == '100%'
    end
    return false
end

function StateModule:isRoomPoweredOn(room)
    if room == "RmA" then
        return components.rmAPowerState and not components.rmAPowerState['selector_0'].Boolean
    elseif room == "RmB" then
        return components.rmBPowerState and not components.rmBPowerState['selector_0'].Boolean
    end
    return false
end

-------------------[ Main Controller Class ]-------------------
local AudioSourceRoutingController = {}
AudioSourceRoutingController.__index = AudioSourceRoutingController

function AudioSourceRoutingController.new(config)
    local self = setmetatable({}, AudioSourceRoutingController)
    
    self.debugging = (config and config.debugging) or true
    self.audioRoutingModule = AudioRoutingModule.new(self)
    self.stateModule = StateModule.new(self)
    
    -- Source routing configuration for EMC combined mode
    self.emcRoutingConfig = {
        [4] = { key = "Combined_RmA_Laptop", room = "RmA", source = "Laptop" },
        [5] = { key = "Combined_RmA_PC", room = "RmA", source = "PC" },
        [6] = { key = "Combined_RmB_Laptop", room = "RmB", source = "Laptop" },
        [7] = { key = "Combined_RmB_PC", room = "RmB", source = "PC" },
        [9] = { key = "Combined_RmA_WPres", room = "RmA", source = "WPres" },
        [10] = { key = "Combined_RmB_WPres", room = "RmB", source = "WPres" }
    }
    
    -- Source routing configuration for Room A divided mode
    self.rmARoutingConfig = {
        [3] = { key = "RmA_Laptop", room = "RmA", source = "Laptop" },
        [4] = { key = "RmA_PC", room = "RmA", source = "PC" },
        [5] = { key = "RmA_WPres", room = "RmA", source = "WPres" }
    }
    
    -- Source routing configuration for Room B divided mode
    self.rmBRoutingConfig = {
        [3] = { key = "RmB_Laptop", room = "RmB", source = "Laptop" },
        [4] = { key = "RmB_PC", room = "RmB", source = "PC" },
        [5] = { key = "RmB_WPres", room = "RmB", source = "WPres" }
    }
    
    return self
end

function AudioSourceRoutingController:debugPrint(msg)
    if self.debugging then
        print("[Audio Routing] " .. msg)
    end
end

-------------------[ Routing Logic ]-------------------
function AudioSourceRoutingController:handleEMCSelection(selectorIndex)
    -- Early returns for invalid states
    if not self.stateModule:isCombined() then
        self:debugPrint("System not in combined mode")
        return
    end
    
    if not self.stateModule:isRoomReady("RmA") then
        self:debugPrint("Room A not ready")
        return
    end
    
    -- Get routing config for this selector
    local routeConfig = self.emcRoutingConfig[selectorIndex]
    if not routeConfig then
        self:debugPrint("No routing config for selector " .. selectorIndex)
        return
    end
    
    -- Route audio using combined mode
    self.audioRoutingModule:routeCombinedAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display buttons
    local buttonConfig = self.audioRoutingModule.displayButtonMap[routeConfig.key]
    self.audioRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("EMC routing: " .. routeConfig.key)
end

function AudioSourceRoutingController:handleRoomASelection(selectorIndex)
    -- Early returns for invalid states
    if not self.stateModule:isRoomDivided() then
        self:debugPrint("Rooms not divided")
        return
    end
    
    if not self.stateModule:isRoomReady("RmA") then
        self:debugPrint("Room A not ready")
        return
    end
    
    -- Get routing config for this selector
    local routeConfig = self.rmARoutingConfig[selectorIndex]
    if not routeConfig then
        self:debugPrint("No Room A routing config for selector " .. selectorIndex)
        return
    end
    
    -- Route audio to Room A
    self.audioRoutingModule:routeAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display button for Room A only
    local buttonConfig = self.audioRoutingModule.displayButtonMap[routeConfig.key]
    self.audioRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("Room A routing: " .. routeConfig.key)
end

function AudioSourceRoutingController:handleRoomBSelection(selectorIndex)
    -- Early returns for invalid states
    if not self.stateModule:isRoomDivided() then
        self:debugPrint("Rooms not divided")
        return
    end
    
    if not self.stateModule:isRoomReady("RmB") then
        self:debugPrint("Room B not ready")
        return
    end
    
    -- Get routing config for this selector
    local routeConfig = self.rmBRoutingConfig[selectorIndex]
    if not routeConfig then
        self:debugPrint("No Room B routing config for selector " .. selectorIndex)
        return
    end
    
    -- Route audio to Room B
    self.audioRoutingModule:routeAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display button for Room B only
    local buttonConfig = self.audioRoutingModule.displayButtonMap[routeConfig.key]
    self.audioRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("Room B routing: " .. routeConfig.key)
end

-------------------[ Event Handler Registration ]-------------------
function AudioSourceRoutingController:registerEventHandlers()
    -- System initialization handler
    if components.initTrigger then
        bind(components.initTrigger['percent_output'], function(ctl)
            if ctl.Position == 1 then
                self.audioRoutingModule:muteAllRooms()
                self:debugPrint("System initialized - all sources muted")
            end
        end)
    end
    
    -- EMC UCI Layer Selector handler
    if components.emcUCISelector then
        bind(components.emcUCISelector['selector'], function(ctl)
            -- Determine which selector button is active
            for i = 4, 10 do
                if components.emcUCISelector['selector_' .. i] and 
                   components.emcUCISelector['selector_' .. i].Boolean then
                    self:handleEMCSelection(i)
                    return
                end
            end
            
            -- If no valid selector is active and not combined, mute all
            if not self.stateModule:isCombined() then
                self.audioRoutingModule:muteAllRooms()
            end
        end)
    end
    
    -- Room A UCI Layer Selector handler
    if components.rmAUCISelector then
        bind(components.rmAUCISelector['selector'], function(ctl)
            -- Determine which selector button is active
            for i = 3, 5 do
                if components.rmAUCISelector['selector_' .. i] and 
                   components.rmAUCISelector['selector_' .. i].Boolean then
                    self:handleRoomASelection(i)
                    return
                end
            end
        end)
    end
    
    -- Room B UCI Layer Selector handler
    if components.rmBUCISelector then
        bind(components.rmBUCISelector['selector'], function(ctl)
            -- Determine which selector button is active
            for i = 3, 5 do
                if components.rmBUCISelector['selector_' .. i] and 
                   components.rmBUCISelector['selector_' .. i].Boolean then
                    self:handleRoomBSelection(i)
                    return
                end
            end
        end)
    end
    
    -- Room A power state handler
    if components.rmAPowerState then
        bind(components.rmAPowerState['selector_0'], function(ctl)
            if ctl.Boolean then
                self.audioRoutingModule:muteAllChannels(components.rmAMixer)
                self:debugPrint("Room A powered off - muted")
            end
        end)
    end
    
    -- Room B power state handler
    if components.rmBPowerState then
        bind(components.rmBPowerState['selector_0'], function(ctl)
            if ctl.Boolean then
                self.audioRoutingModule:muteAllChannels(components.rmBMixer)
                self:debugPrint("Room B powered off - muted")
            end
        end)
    end
end

-------------------[ Initialization ]-------------------
function AudioSourceRoutingController:init()
    self:debugPrint("Initializing Audio Source Routing Controller")
    self:registerEventHandlers()
    
    -- Initial state - mute all
    self.audioRoutingModule:muteAllRooms()
    
    self:debugPrint("Initialization complete")
end

-------------------[ Cleanup ]-------------------
function AudioSourceRoutingController:cleanup()
    self:debugPrint("Cleanup started")
    
    -- Clear all event handlers
    if components.initTrigger then
        components.initTrigger['percent_output'].EventHandler = nil
    end
    if components.emcUCISelector then
        components.emcUCISelector['selector'].EventHandler = nil
    end
    if components.rmAUCISelector then
        components.rmAUCISelector['selector'].EventHandler = nil
    end
    if components.rmBUCISelector then
        components.rmBUCISelector['selector'].EventHandler = nil
    end
    if components.rmAPowerState then
        components.rmAPowerState['selector_0'].EventHandler = nil
    end
    if components.rmBPowerState then
        components.rmBPowerState['selector_0'].EventHandler = nil
    end
    
    self:debugPrint("Cleanup complete")
end

-------------------[ Factory Function ]-------------------
local function createAudioRoutingController(config)
    print("Creating Audio Source Routing Controller...")
    
    local success, result = pcall(function()
        local instance = AudioSourceRoutingController.new(config or { debugging = true })
        if not instance then return nil end
        
        instance:init()
        return instance
    end)
    
    if success and result then
        print("✓ Audio Source Routing Controller created successfully")
        return result
    else
        local errorMsg = success and "Instance creation failed" or tostring(result)
        print("✗ ERROR: Failed to create Audio Source Routing Controller: " .. errorMsg)
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
-- Validate components before creating controller
if not validateComponents() then
    print("ERROR: Cannot create Audio Source Routing Controller - component validation failed")
    return
end

-- Export class globally for potential multiple instances
_G.AudioSourceRoutingController = AudioSourceRoutingController

-- Create default instance
local myAudioRoutingController = createAudioRoutingController({ debugging = true })

if myAudioRoutingController then
    -- Export instance globally for external access
    _G.myAudioRoutingController = myAudioRoutingController
    print("Audio Source Routing Controller ready!")
else
    print("ERROR: Audio Source Routing Controller NOT created")
end

-------------------[ Public API ]-------------------
--[[
Public API:
    -- Manual routing control
    myAudioRoutingController.audioRoutingModule:routeAudio("RmA", "Laptop")
    myAudioRoutingController.audioRoutingModule:routeAudio("RmB", "PC")
    myAudioRoutingController.audioRoutingModule:routeCombinedAudio("RmA", "WPres")
    
    -- Mute controls
    myAudioRoutingController.audioRoutingModule:muteAllRooms()
    myAudioRoutingController.audioRoutingModule:muteAllChannels(components.rmAMixer)
    
    -- State queries
    local isCombined = myAudioRoutingController.stateModule:isCombined()
    local isDivided = myAudioRoutingController.stateModule:isRoomDivided()
    local isAReady = myAudioRoutingController.stateModule:isRoomReady("RmA")
    local isBPowered = myAudioRoutingController.stateModule:isRoomPoweredOn("RmB")
    
    -- Cleanup
    myAudioRoutingController:cleanup()
]]

