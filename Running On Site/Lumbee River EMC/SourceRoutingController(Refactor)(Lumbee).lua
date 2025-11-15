--[[
    Source Routing Controller (Refactored)
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
    initTrigger = Component.New('trigSystemInitialize'),
    emcUCISelector = Component.New('uciLayerSelectorEMC'),
    rmAUCISelector = Component.New('uciLayerSelectorRmA'),
    rmBUCISelector = Component.New('uciLayerSelectorRmB'),
    rmBPowerState = Component.New('selPowerStateRmB'),
    rmAPowerState = Component.New('selPowerStateRmA'),
    rmBMixer = Component.New('mixerPGMRmB'),
    rmAMixer = Component.New('mixerPGMRmA'),
    combinerSS = Component.New('snapshotCombinerEMC'),
    rmAStatusBar = Component.New('barStatusRmA'),
    displayControlsA = Component.New('compDisplayControlsRoomA'),
    rmBStatusBar = Component.New('barStatusRmB'),
    displayControlsB = Component.New('compDisplayControlsRoomB'),
    emcDisplayController = Component.New('compDisplayControlsMain'),
    routerPGM = Component.New('routerPGM')
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
        print("ERROR: SourceRoutingController missing required components:")
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

-------------------[ Source Routing Module ]-------------------
local SourceRoutingModule = setmetatable({}, BaseModule)
SourceRoutingModule.__index = SourceRoutingModule

function SourceRoutingModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "SourceRouting"), SourceRoutingModule)
    
    -- Configuration-driven routing maps for DRY pattern
    self.mixerChannelMap = {
        Laptop = { channels = {1, 4}, delay = 0.2 },
        PC = { channels = {3, 5}, delay = 0.2 },
        WPres = { channels = {2}, delay = 0.2 },
        -- DispatchPC01 and DispatchPC02 do not contain audio channels
        SignagePC = { channels = {6}, delay = 0.2 },
        MediaPlayer = { channels = {7}, delay = 0.2 },
    }
    
    -- Display button mappings for each source
    self.displayButtonMap = {
        RmA_DispatchPC01 = { roomA = 1, roomB = nil },
        RmA_DispatchPC02 = { roomA = 2, roomB = nil },
        RmB_DispatchPC01 = { roomA = nil, roomB = 1 },
        RmB_DispatchPC02 = { roomA = nil, roomB = 2 },
        RmA_SignagePC = { roomA = 11, roomB = nil},
        RmB_SignagePC = { roomA = nil, roomB = 11},
        RmA_MediaPlayer = { roomA = 12, roomB = nil},
        RmB_MediaPlayer = { roomA = nil, roomB = 12},
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
        Combined_RmB_WPres = { roomA = 6, roomB = 6 },
        Combined_DispatchPC01 = { roomA = 1, roomB = 1 },
        Combined_DispatchPC02 = { roomA = 2, roomB = 2 },
        Combined_SignagePC = { roomA = 11, roomB = 11},
        Combined_MediaPlayer = { roomA = 12, roomB = 12},
    }
    
    return self
end

function SourceRoutingModule:muteAllChannels(mixer)
    if not mixer then return end
    
    for i = 1, 7 do
        setProp(mixer['input_' .. i .. '_mute'], "Boolean", true)
    end
    self:debug("Muted all channels on " .. (mixer == components.rmAMixer and "Room A" or "Room B") .. " mixer")
end

function SourceRoutingModule:muteAllRooms()
    self:muteAllChannels(components.rmAMixer)
    self:muteAllChannels(components.rmBMixer)
    self:debug("Muted all channels in both rooms")
end

function SourceRoutingModule:unmuteChannels(mixer, sourceType)
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

function SourceRoutingModule:routeAudio(room, sourceType)
    local mixer = (room == "RmA") and components.rmAMixer or 
                  (room == "RmB") and components.rmBMixer or nil
    
    if not mixer then
        self:debug("Invalid room: " .. tostring(room))
        return
    end
    
    self:unmuteChannels(mixer, sourceType)
    self:debug("Routed audio: " .. room .. " -> " .. sourceType)
end

function SourceRoutingModule:routeCombinedAudio(sourceRoom, sourceType)
    -- For combined mode, route to both mixers but only unmute the source room's channels
    local sourceMixer = (sourceRoom == "RmA") and components.rmAMixer or components.rmBMixer
    
    -- Mute all channels in both rooms first
    self:muteAllRooms()
    
    -- Get config for delay and channels
    local config = self.mixerChannelMap[sourceType]
    if not config then return end
    
    -- Unmute only the source room's channels
    Timer.CallAfter(function()
        for _, channel in ipairs(config.channels) do
            setProp(sourceMixer['input_' .. channel .. '_mute'], "Boolean", false)
        end
    end, config.delay)
    
    self:debug("Routed combined audio: " .. sourceRoom .. " -> " .. sourceType)
end

function SourceRoutingModule:triggerDisplayButton(buttonConfig)
    if not buttonConfig then return end
    
    if buttonConfig.roomA and components.displayControlsA then
        local btn = components.displayControlsA['btnSource ' .. buttonConfig.roomA]
        if btn and btn.Trigger then btn:Trigger() end
    end
    
    if buttonConfig.roomB and components.displayControlsB then
        local btn = components.displayControlsB['btnSource ' .. buttonConfig.roomB]
        if btn and btn.Trigger then btn:Trigger() end
    end
end

function SourceRoutingModule:handleEMCDisplayButtonPress(buttonIndex)
    -- Map button index to source type and configuration
    local buttonToSourceMap = {
        [1] = { key = "Combined_DispatchPC01", source = nil },  -- No audio
        [2] = { key = "Combined_DispatchPC02", source = nil },  -- No audio
        [11] = { key = "Combined_SignagePC", source = "SignagePC" },
        [12] = { key = "Combined_MediaPlayer", source = "MediaPlayer" }
    }
    
    local sourceConfig = buttonToSourceMap[buttonIndex]
    if not sourceConfig then return end
    
    -- Trigger display buttons for both rooms
    local buttonConfig = self.displayButtonMap[sourceConfig.key]
    self:triggerDisplayButton(buttonConfig)
    
    -- Route audio if source has audio channels
    if sourceConfig.source then
        -- Mute all channels first
        self:muteAllRooms()
        
        -- Unmute the source channels on Room A mixer only (to avoid doubling audio in combined space)
        local config = self.mixerChannelMap[sourceConfig.source]
        if config then
            Timer.CallAfter(function()
                for _, channel in ipairs(config.channels) do
                    setProp(components.rmAMixer['input_' .. channel .. '_mute'], "Boolean", false)
                end
            end, config.delay)
        end
    end
    
    self:debug("EMC display button " .. buttonIndex .. " pressed: " .. sourceConfig.key)
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
        return components.rmAPowerState and not components.rmAPowerState['selector.0'].Boolean
    elseif room == "RmB" then
        return components.rmBPowerState and not components.rmBPowerState['selector.0'].Boolean
    end
    return false
end

-------------------[ Main Controller Class ]-------------------
local SourceRoutingController = {}
SourceRoutingController.__index = SourceRoutingController

function SourceRoutingController.new(config)
    local self = setmetatable({}, SourceRoutingController)
    
    self.debugging = (config and config.debugging) or true
    self.sourceRoutingModule = SourceRoutingModule.new(self)
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

function SourceRoutingController:debugPrint(msg)
    if self.debugging then
        print("[Source Routing] " .. msg)
    end
end

-------------------[ Routing Logic ]-------------------
function SourceRoutingController:handleEMCSelection(selectorIndex)
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
    self.sourceRoutingModule:routeCombinedAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display buttons
    local buttonConfig = self.sourceRoutingModule.displayButtonMap[routeConfig.key]
    self.sourceRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("EMC routing: " .. routeConfig.key)
end

function SourceRoutingController:handleRoomASelection(selectorIndex)
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
    self.sourceRoutingModule:routeAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display button for Room A only
    local buttonConfig = self.sourceRoutingModule.displayButtonMap[routeConfig.key]
    self.sourceRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("Room A routing: " .. routeConfig.key)
end

function SourceRoutingController:handleRoomBSelection(selectorIndex)
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
    self.sourceRoutingModule:routeAudio(routeConfig.room, routeConfig.source)
    
    -- Trigger display button for Room B only
    local buttonConfig = self.sourceRoutingModule.displayButtonMap[routeConfig.key]
    self.sourceRoutingModule:triggerDisplayButton(buttonConfig)
    
    self:debugPrint("Room B routing: " .. routeConfig.key)
end

-------------------[ Event Handler Registration ]-------------------
function SourceRoutingController:registerEventHandlers()
    -- System initialization handler
    if components.initTrigger then
        bind(components.initTrigger['percent_output'], function(ctl)
            if ctl.Position == 1 then
                self.sourceRoutingModule:muteAllRooms()
                self:debugPrint("System initialized - all sources muted")
            end
        end)
    end
    
    -- EMC UCI Layer Selector handler
    if components.emcUCISelector then
        bind(components.emcUCISelector['selector'], function(ctl)
            -- Determine which selector button is active
            for i = 4, 10 do
                if components.emcUCISelector['selector.' .. i] and 
                   components.emcUCISelector['selector.' .. i].Boolean then
                    self:handleEMCSelection(i)
                    return
                end
            end
            
            -- If no valid selector is active and not combined, mute all
            if not self.stateModule:isCombined() then
                self.sourceRoutingModule:muteAllRooms()
            end
        end)
    end
    
    -- Room A UCI Layer Selector handler
    if components.rmAUCISelector then
        bind(components.rmAUCISelector['selector'], function(ctl)
            -- Determine which selector button is active
            for i = 3, 5 do
                if components.rmAUCISelector['selector.' .. i] and 
                   components.rmAUCISelector['selector.' .. i].Boolean then
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
                if components.rmBUCISelector['selector.' .. i] and 
                   components.rmBUCISelector['selector.' .. i].Boolean then
                    self:handleRoomBSelection(i)
                    return
                end
            end
        end)
    end
    
    -- Room A power state handler
    if components.rmAPowerState then
        bind(components.rmAPowerState['selector.0'], function(ctl)
            if ctl.Boolean then
                self.sourceRoutingModule:muteAllChannels(components.rmAMixer)
                self:debugPrint("Room A powered off - muted")
            end
        end)
    end
    
    -- Room B power state handler
    if components.rmBPowerState then
        bind(components.rmBPowerState['selector.0'], function(ctl)
            if ctl.Boolean then
                self.sourceRoutingModule:muteAllChannels(components.rmBMixer)
                self:debugPrint("Room B powered off - muted")
            end
        end)
    end
    
    -- EMC Main Display Controller button handlers for Combined mode sources
    if components.emcDisplayController then
        -- DispatchPC01 button (no audio)
        bind(components.emcDisplayController['btnSource 1'], function(ctl)
            if ctl.Boolean and self.stateModule:isCombined() then
                self.sourceRoutingModule:handleEMCDisplayButtonPress(1)
            end
        end)
        
        -- DispatchPC02 button (no audio)
        bind(components.emcDisplayController['btnSource 2'], function(ctl)
            if ctl.Boolean and self.stateModule:isCombined() then
                self.sourceRoutingModule:handleEMCDisplayButtonPress(2)
            end
        end)
        
        -- SignagePC button (has audio - channel 6)
        bind(components.emcDisplayController['btnSource 11'], function(ctl)
            if ctl.Boolean and self.stateModule:isCombined() then
                self.sourceRoutingModule:handleEMCDisplayButtonPress(11)
            end
        end)
        
        -- MediaPlayer button (has audio - channel 7)
        bind(components.emcDisplayController['btnSource 12'], function(ctl)
            if ctl.Boolean and self.stateModule:isCombined() then
                self.sourceRoutingModule:handleEMCDisplayButtonPress(12)
            end
        end)
    end
end

-------------------[ Initialization ]-------------------
function SourceRoutingController:init()
    self:debugPrint("Initializing Source Routing Controller")
    self:registerEventHandlers()
    
    -- Initial state - mute all
    self.sourceRoutingModule:muteAllRooms()
    
    self:debugPrint("Initialization complete")
end

-------------------[ Cleanup ]-------------------
function SourceRoutingController:cleanup()
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
        components.rmAPowerState['selector.0'].EventHandler = nil
    end
    if components.rmBPowerState then
        components.rmBPowerState['selector.0'].EventHandler = nil
    end
    if components.emcDisplayController then
        components.emcDisplayController['btnSource 1'].EventHandler = nil
        components.emcDisplayController['btnSource 2'].EventHandler = nil
        components.emcDisplayController['btnSource 11'].EventHandler = nil
        components.emcDisplayController['btnSource 12'].EventHandler = nil
    end
    
    self:debugPrint("Cleanup complete")
end

-------------------[ Factory Function ]-------------------
local function createSourceRoutingController(config)
    print("Creating Source Routing Controller...")
    
    local success, result = pcall(function()
        local instance = SourceRoutingController.new(config or { debugging = true })
        if not instance then return nil end
        
        instance:init()
        return instance
    end)
    
    if success and result then
        print("✓ Source Routing Controller created successfully")
        return result
    else
        local errorMsg = success and "Instance creation failed" or tostring(result)
        print("✗ ERROR: Failed to create Source Routing Controller: " .. errorMsg)
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
-- Validate components before creating controller
if not validateComponents() then
    print("ERROR: Cannot create Source Routing Controller - component validation failed")
    return
end

-- Export class globally for potential multiple instances
_G.SourceRoutingController = SourceRoutingController

-- Create default instance
local mySourceRoutingController = createSourceRoutingController({ debugging = true })

if mySourceRoutingController then
    -- Export instance globally for external access
    _G.mySourceRoutingController = mySourceRoutingController
    print("Source Routing Controller ready!")
else
    print("ERROR: Source Routing Controller NOT created")
end

-------------------[ Public API ]-------------------
--[[
Public API:
    -- Manual routing control
    mySourceRoutingController.sourceRoutingModule:routeAudio("RmA", "Laptop")
    mySourceRoutingController.sourceRoutingModule:routeAudio("RmB", "PC")
    mySourceRoutingController.sourceRoutingModule:routeCombinedAudio("RmA", "WPres")
    
    -- Mute controls
    mySourceRoutingController.sourceRoutingModule:muteAllRooms()
    mySourceRoutingController.sourceRoutingModule:muteAllChannels(components.rmAMixer)
    
    -- State queries
    local isCombined = mySourceRoutingController.stateModule:isCombined()
    local isDivided = mySourceRoutingController.stateModule:isRoomDivided()
    local isAReady = mySourceRoutingController.stateModule:isRoomReady("RmA")
    local isBPowered = mySourceRoutingController.stateModule:isRoomPoweredOn("RmB")
    
    -- Cleanup
    mySourceRoutingController:cleanup()
]]

