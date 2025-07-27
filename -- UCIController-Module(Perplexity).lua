-- All code in one file, no require() or modules

-- === Utility Functions & Helpers ===
local function log(msg)
    print("[LOG] "..tostring(msg))
end

local function warn(msg)
    print("[WARN] "..tostring(msg))
end

local function safeControl(name, prop)
    if not Controls[name] then
        warn("Control '"..tostring(name).."' not found")
        return nil
    end
    if prop then
        if Controls[name][prop] == nil then
            warn("Property '"..tostring(prop).."' not found on control '"..tostring(name).."'")
            return nil
        end
        return Controls[name][prop]
    end
    return Controls[name]
end

local function buildControlArray(list)
    local arr = {}
    for i, name in ipairs(list) do arr[i] = Controls[name] or nil end
    return arr
end

local function buildVariableArray(list)
    local arr = {}
    for i, name in ipairs(list) do arr[i] = Uci.Variables[name] or nil end
    return arr
end

-- === Configuration (can be edited) ===
local navButtons = { "btnNav01","btnNav02","btnNav03","btnNav04","btnNav05","btnNav06",
                     "btnNav07","btnNav08","btnNav09","btnNav10","btnNav11","btnNav12" }
local legendControls = { "txtNav01","txtNav02","txtNav03","txtNav04","txtNav05","txtNav06",
                         "txtNav07","txtNav08","txtNav09","txtNav10","txtNav11","txtNav12" }
local userLabelVariables = { "txtLabelNav01","txtLabelNav02","txtLabelNav03", "txtLabelNav04", "txtLabelNav05", "txtLabelNav06",
                             "txtLabelNav07","txtLabelNav08","txtLabelNav09","txtLabelNav10","txtLabelNav11","txtLabelNav12" }
local routingButtons = { "btnRouting01","btnRouting02","btnRouting03","btnRouting04","btnRouting05" }
local routingLayers = { "R01-Routing-Lobby", "R02-Routing-WTerrace", "R03-Routing-NTerraceWall",
                        "R04-Routing-Garden", "R05-Routing-NTerraceFloor" }

local switcherTypes = {
    NV32 = {
        name = "NV32",
        componentType = "streamer_hdmi_switcher",
        variableNames = {"devNV32","codenameNV32"},
        routingMethod = "hdmi.out.1.select.index",
        defaultMapping = { [7]=5, [8]=4, [9]=6 }
    },
    ExtronDXP = {
        name = "Extron DXP",
        componentType = "extron.type",
        variableNames = {"devExtronDXP"},
        routingMethod = "output.1",
        defaultMapping = { [7]=2, [8]=4, [9]=1 }
    },
    Generic = {
        name = "Generic",
        componentType = nil,
        variableNames = {"devVideoSwitcher"},
        routingMethod = "output.1",
        defaultMapping = { [7]=1, [8]=2, [9]=3 }
    }
}

-- === VideoSwitcherIntegration ===
local VideoSwitcherIntegration = {}
VideoSwitcherIntegration.__index = VideoSwitcherIntegration
function VideoSwitcherIntegration.new()
    local self = setmetatable({}, VideoSwitcherIntegration)
    self.switcherTypes = switcherTypes
    self.isEnabled = false
    self.previousButtonStates = {}
    self.uciToInputMapping = {}
    self.switcherComponent = nil
    self.switcherType = nil
    return self
end

function VideoSwitcherIntegration:initialize()
    -- (Insert discovery/detection/init logic from your original script)
    -- For demo, always enable Generic
    self.switcherType = "Generic"
    self.uciToInputMapping = self.switcherTypes.Generic.defaultMapping
    self.isEnabled = true
    log("VideoSwitcherIntegration initialized as " .. self.switcherType)
end

function VideoSwitcherIntegration:switchViaNavButton(btnIdx)
    if not self.isEnabled then warn("Video switcher not enabled") return end
    local input = self.uciToInputMapping[btnIdx]
    if input then
        log("Switching video to input "..tostring(input).." for nav button "..tostring(btnIdx))
        -- Actual switching logic here as per your existing code
    else
        warn("No mapping for nav button "..tostring(btnIdx))
    end
end

function VideoSwitcherIntegration:cleanup()
    -- Cleanup logic (stop timers, etc) if present
end

-- === RoomAutomationController ===
local RoomAutomationController = {}
RoomAutomationController.__index = RoomAutomationController
function RoomAutomationController.new()
    local self = setmetatable({}, RoomAutomationController)
    return self
end

function RoomAutomationController:initialize()
    -- Any init you need
end

function RoomAutomationController:powerOnRoom()
    log("Room power ON requested")
    -- (Insert your power-on logic here)
end

function RoomAutomationController:cleanup()
    -- Any cleanup needed
end

-- === UCIController ===
local UCIController = {}
UCIController.__index = UCIController
function UCIController.new()
    local self = setmetatable({}, UCIController)
    self.uciPage = "UCI_Main"
    self.arrbtnNavs = buildControlArray(navButtons)
    self.arrUCILegends = buildControlArray(legendControls)
    self.arrUCIUserLabels = buildVariableArray(userLabelVariables)
    self.arrRoutingButtons = buildControlArray(routingButtons)
    self.routingLayers = routingLayers
    self.activeRoutingLayer = 1
    self.layerStates = {}
    self.videoSwitcher = VideoSwitcherIntegration.new()
    self.roomAutomation = RoomAutomationController.new()
    self.isInitialized = false
    self:registerEventHandlers()
    self:initialize()
    return self
end

function UCIController:registerEventHandlers()
    for i, btn in ipairs(self.arrRoutingButtons) do
        if btn then
            btn.EventHandler = function()
                self.activeRoutingLayer = i
                log("Routing layer switched to: " .. tostring(i))
                -- Do any other action for routing
            end
        end
    end
    -- etc for other buttons
end

function UCIController:initialize()
    self.videoSwitcher:initialize()
    self.roomAutomation:initialize()
    self.isInitialized = true
    log("UCIController initialized for " .. self.uciPage)
end

function UCIController:cleanup()
    self.videoSwitcher:cleanup()
    self.roomAutomation:cleanup()
end

-- Example usage:
local uci = UCIController.new()
-- uci:cleanup() -- call to clean up, if needed on script teardown

