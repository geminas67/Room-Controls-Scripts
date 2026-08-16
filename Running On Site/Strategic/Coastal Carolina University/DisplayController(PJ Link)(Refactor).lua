--[[
  PJLink DisplayController - Q-SYS Control Script
  Controls PJLink displays with power management and input switching
  Integrates with SystemAutomationController
]]--

local displayControls = {
    displayPowerOn = "PowerOn",
    displayPowerOff = "PowerOff",
    displayPowerStatus = "PowerStatus",
    currentInput = "VideoInput"
}

local inputControls = {
    ["Digital 1"] = "Digital 1",
    ["Digital 2"] = "Digital 2",
    ["Digital 3"] = "Digital 3",
    ["Digital 4"] = "Digital 4",
    ["RGB 1"] = "RGB 1",
    ["Video 1"] = "Video 1"
}

local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
    compRoomControls = Controls.compRoomControls,
    roomName = Controls.roomName,
    ledDisplayPower = Controls.ledDisplayPower,
    ledDisplayInput = Controls.ledDisplayInput,
    ledDisplayWarming = Controls.ledDisplayWarming,
    ledDisplayCooling = Controls.ledDisplayCooling,
    btnDisplayPowerAll = Controls.btnDisplayPowerAll,
    btnDisplayPowerOn = Controls.btnDisplayPowerOn,
    btnDisplayPowerOff = Controls.btnDisplayPowerOff,
    btnDisplayPowerToggle = Controls.btnDisplayPowerToggle,
    btnDisplayInputAll = Controls.btnDisplayInputAll,
    btnAVMute = Controls.btnAVMute
}

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    if not ctrls then return end
    local array = isArr(ctrls) and ctrls or { ctrls }
    for i, ctrl in ipairs(array) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

local function normalizeControlArrays()
    for _, name in ipairs({'devDisplays', 'btnDisplayPowerOn', 'btnDisplayPowerOff', 'btnDisplayPowerToggle'}) do
        local ctrl = controls[name]
        if ctrl and not isArr(ctrl) then controls[name] = {ctrl} end
    end
end

local function validateControls()
    for _, name in ipairs({"txtStatus", "devDisplays"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

-------------------[ Controller ]-------------------
PJLinkDisplayController = {}
PJLinkDisplayController.__index = PJLinkDisplayController

function PJLinkDisplayController.new(roomName, config)
    if not validateControls() then return nil end
    normalizeControlArrays()
    
    local self = setmetatable({}, PJLinkDisplayController)
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.componentTypes = {
        displays = "%PLUGIN%_80a40a84-e685-4b13-a5c4-fbdc12bd85e6_%FP%_cac5837f40ef3a83d7365386eb4b8d16", -- PJLink Display
        roomControls = "device_controller_script"
    }
    self.components = { displays = {}, compRoomControls = nil, invalid = {} }
    self.state = { lastInput = "Digital 1", powerState = false, isWarming = false, isCooling = false }
    self.config = { maxDisplays = config and config.maxDisplays or 9, defaultInput = "Digital 1" }
    self.timers = { warmup = Timer.New(), cooldown = Timer.New() }
    self.timerConfig = { warmupTime = 7, cooldownTime = 5 }
    
    return self
end

function PJLinkDisplayController:debugPrint(msg)
    if self.debugging then print("["..self.roomName.."] "..msg) end
end

function PJLinkDisplayController:updateTimerConfig()
    if not self.components.compRoomControls then 
        self:debugPrint("No room controls component found - Using default timing values")
        return 
    end
    local comp = self.components.compRoomControls
    local warmup = comp.warmupTime and comp.warmupTime.Value
    local cooldown = comp.cooldownTime and comp.cooldownTime.Value
    if warmup and warmup > 0 then self.timerConfig.warmupTime = warmup end
    if cooldown and cooldown > 0 then self.timerConfig.cooldownTime = cooldown end
    self:debugPrint("Timer config - Warmup: " .. self.timerConfig.warmupTime .. "s, Cooldown: " .. self.timerConfig.cooldownTime .. "s")
end

function PJLinkDisplayController:safeAccess(component, control, action, value)
    local success, result = pcall(function()
        if not component or not component[control] then return false end
        if action == "trigger" then component[control]:Trigger(); return true end
        if action == "get" then return component[control].Boolean end
        if action == "set" then component[control].Boolean = value; return true end
        if action == "getString" then return component[control].String end
    end)
    return success and result or false
end

-------------------[ Display Methods ]-------------------
function PJLinkDisplayController:powerAll(state)
    self:debugPrint("Powering all displays: " .. tostring(state))
    local control = state and displayControls.displayPowerOn or displayControls.displayPowerOff
    for i, display in pairs(self.components.displays) do
        if display then self:safeAccess(display, control, "trigger") end
    end
    self.state.powerState = state
    setProp(controls.ledDisplayPower, "Boolean", state)
end

function PJLinkDisplayController:powerSingle(index, state)
    self:debugPrint("Powering display " .. index .. " to: " .. tostring(state))
    local display = self.components.displays[index]
    local control = state and displayControls.displayPowerOn or displayControls.displayPowerOff
    if display then self:safeAccess(display, control, "trigger") end
end

function PJLinkDisplayController:setInputAll(input)
    self:debugPrint("Setting all displays to input: " .. input)
    for i, display in pairs(self.components.displays) do
        local controlName = inputControls[input]
        if display and controlName and display[controlName] then
            self:debugPrint("Setting display " .. i .. " input to: " .. input)
            self:safeAccess(display, controlName, "trigger")
        else
            self:debugPrint("Input control not found for: " .. tostring(input))
        end
    end
    self.state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

function PJLinkDisplayController:getDisplayCount()
    local count = 0
    for _ in pairs(self.components.displays) do count = count + 1 end
    return count
end

-------------------[ Power Methods ]-------------------
function PJLinkDisplayController:enablePowerControls(state)
    for _, name in ipairs({"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerToggle", "btnDisplayPowerAll", "btnDisplayInputAll"}) do
        local ctrl = controls[name]
        if isArr(ctrl) then
            for _, btn in ipairs(ctrl) do setProp(btn, "IsDisabled", not state) end
        else
            setProp(ctrl, "IsDisabled", not state)
        end
    end
end

function PJLinkDisplayController:enablePowerControlIndex(index, state)
    for _, name in ipairs({"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerToggle"}) do
        local ctrl = controls[name]
        if ctrl and ctrl[index] then setProp(ctrl[index], "IsDisabled", not state) end
    end
end

function PJLinkDisplayController:updatePowerFeedback()
    local allOn, count = true, 0
    for i, display in pairs(self.components.displays) do
        if display then
            count = count + 1
            local powerStatus = self:safeAccess(display, displayControls.displayPowerStatus, "getString")
            if controls.btnDisplayPowerToggle and controls.btnDisplayPowerToggle[i] then
                setProp(controls.btnDisplayPowerToggle[i], "Boolean", powerStatus == "On")
            end
            if powerStatus ~= "On" then allOn = false end
        end
    end
    if count > 0 then
        setProp(controls.ledDisplayPower, "Boolean", allOn)
        setProp(controls.btnDisplayPowerAll, "Boolean", allOn)
        self.state.powerState = allOn
        self:debugPrint("Power feedback updated - Powered: " .. count .. "/" .. self:getDisplayCount())
    end
end

function PJLinkDisplayController:powerOnDisplay(index)
    self:debugPrint("Powering on display " .. index)
    self:powerSingle(index, true)
    self:enablePowerControlIndex(index, false)
    self:setOppositePowerButtonLegend(index, true)
    self.state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    self.timers.warmup:Start(self.timerConfig.warmupTime)
end

function PJLinkDisplayController:powerOffDisplay(index)
    self:debugPrint("Powering off display " .. index)
    self:powerSingle(index, false)
    self:enablePowerControlIndex(index, false)
    self:setOppositePowerButtonLegend(index, false)
    self.state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    self.timers.cooldown:Start(self.timerConfig.cooldownTime)
end

function PJLinkDisplayController:powerOnAll()
    self:debugPrint("Powering on all displays")
    self:powerAll(true)
    self:enablePowerControls(false)
    self.state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    setProp(controls.ledDisplayPower, "Boolean", true)
    setProp(controls.btnDisplayPowerAll, "Boolean", true)
    self.timers.warmup:Start(self.timerConfig.warmupTime)
end

function PJLinkDisplayController:powerOffAll()
    self:debugPrint("Powering off all displays")
    self:powerAll(false)
    self:enablePowerControls(false)
    self.state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    setProp(controls.ledDisplayPower, "Boolean", false) 
    setProp(controls.btnDisplayPowerAll, "Boolean", false)
    self.timers.cooldown:Start(self.timerConfig.cooldownTime)
end

function PJLinkDisplayController:setOppositePowerButtonLegend(index, poweringOn)
    local targetControl = poweringOn and controls.btnDisplayPowerOff or controls.btnDisplayPowerOn
    if targetControl and targetControl[index] then targetControl[index].Legend = "Please\nwait" end
end

function PJLinkDisplayController:resetButtonLegends(index)
    self:debugPrint("Resetting button legends for [ Display "..index.."]")
    if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
        controls.btnDisplayPowerOn[index].Legend = "On"
    end
    if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
        controls.btnDisplayPowerOff[index].Legend = "Off"
    end
end

-------------------[ Component Management ]-------------------
function PJLinkDisplayController:setComponent(ctrl, componentType)
    local name = ctrl and ctrl.String
    if not name or name == "" or name == self.clearString then
        self:debugPrint("Invalid component selected: " .. tostring(name))
        if ctrl then ctrl.Color = "white" end
        self.components.invalid[componentType] = false
        self:checkStatus()
        return nil
    end
    local comp = Component.New(name)
    if #Component.GetControls(comp) < 1 then
        self:debugPrint("Invalid component found: " .. tostring(name))
        if ctrl then ctrl.String = "[Invalid]"; ctrl.Color = "pink" end
        self.components.invalid[componentType] = true
        self:checkStatus()
        return nil
    end
    self:debugPrint("Component set: " .. tostring(name))
    if ctrl then ctrl.Color = "white" end
    self.components.invalid[componentType] = false
    self:checkStatus()
    return comp
end

function PJLinkDisplayController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v then
            self:debugPrint("Invalid components found")
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    self:debugPrint("Components are valid")
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

function PJLinkDisplayController:setRoomControlsComponent()
    self:debugPrint("Setting room controls component")
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.compRoomControls then self:updateTimerConfig() end
end

function PJLinkDisplayController:setDisplayComponent(index)
    if not Controls.devDisplays or not Controls.devDisplays[index] then return end
    self.components.displays[index] = self:setComponent(Controls.devDisplays[index], "Display ["..index.."]")
    if self.components.displays[index] then
        self:debugPrint("Successfully set up display component " .. index)
        self:setupDisplayEvents(index)
        self:updatePowerFeedback()
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

function PJLinkDisplayController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    if display[displayControls.displayPowerStatus] then
        display[displayControls.displayPowerStatus].EventHandler = function()
            self:updatePowerFeedback()
        end
    end
end

function PJLinkDisplayController:getComponentNames()
    local names = { DisplayNames = {}, RoomControlsNames = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.displays then
            table.insert(names.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and comp.Name:match("^compRoomControls") then
            table.insert(names.RoomControlsNames, comp.Name)
        end
    end
    for _, list in pairs(names) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    if Controls.devDisplays then
        for i = 1, #Controls.devDisplays do
            Controls.devDisplays[i].Choices = names.DisplayNames
        end
        self:debugPrint("Set choices for " .. #Controls.devDisplays .. " display controls")
        self:debugPrint("Found " .. #names.DisplayNames .. " display components")
    end
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = names.RoomControlsNames
    end
end

function PJLinkDisplayController:updateRoomName()
    if not self.components.compRoomControls then return end
    local roomNameCtrl = self.components.compRoomControls["roomName"]
    if roomNameCtrl and roomNameCtrl.String ~= "" then
        self.roomName = "["..roomNameCtrl.String.."]"
        self:debugPrint("Room name updated to: " .. self.roomName)
    end
    self:updateTimerConfig()
end

-------------------[ Event Registration ]-------------------
function PJLinkDisplayController:registerTimers()
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        self:enablePowerControls(true)
        for i = 1, #Controls.devDisplays do
            self:enablePowerControlIndex(i, true)
            self:resetButtonLegends(i)
        end
        self.state.isWarming = false
        setProp(controls.ledDisplayWarming, "Boolean", false)
        self.timers.warmup:Stop()
    end
    
    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        self:enablePowerControls(true)
        for i = 1, #Controls.devDisplays do
            self:enablePowerControlIndex(i, true)
            self:resetButtonLegends(i)
        end
        self.state.isCooling = false
        setProp(controls.ledDisplayCooling, "Boolean", false)
        self.timers.cooldown:Stop()
    end
end

function PJLinkDisplayController:registerEvents()
    bind(controls.compRoomControls, function() self:setRoomControlsComponent() end)
    bind(controls.btnDisplayPowerAll, function(c) if c.Boolean then self:powerOnAll() else self:powerOffAll() end end)
    bind(controls.btnDisplayInputAll, function() self:setInputAll(self.config.defaultInput) end)
    
    bindArray(controls.btnDisplayPowerOn, function(i) self:powerOnDisplay(i) end)
    bindArray(controls.btnDisplayPowerOff, function(i) self:powerOffDisplay(i) end)
    bindArray(controls.btnDisplayPowerToggle, function(i, c) if c.Boolean then self:powerOnDisplay(i) else self:powerOffDisplay(i) end end)
    bindArray(controls.devDisplays, function(i) self:setDisplayComponent(i) end)
end

function PJLinkDisplayController:init()
    self:getComponentNames()
    self:setRoomControlsComponent()
    if Controls.devDisplays then
        for i = 1, #Controls.devDisplays do self:setDisplayComponent(i) end
    end
    self:registerEvents()
    self:registerTimers()
    self:updateRoomName()
    self:updatePowerFeedback()
end

-------------------[ Factory & Initialization ]-------------------
local function getRoomName()
    if Controls.compRoomControls and Controls.compRoomControls.String ~= "" and Controls.compRoomControls.String ~= "[Clear]" then
        local comp = Component.New(Controls.compRoomControls.String)
        if comp and comp["roomName"] and comp["roomName"].String ~= "" then
            return "["..comp["roomName"].String.."]"
        end
    end
    if Controls.roomName and Controls.roomName.String ~= "" then
        return "["..Controls.roomName.String.."]"
    end
    return "[PJLink Display]"
end

local success, controller = pcall(function()
    local instance = PJLinkDisplayController.new(getRoomName(), { debugging = true, maxDisplays = 9 })
    if not instance then error("Validation failed") end
    instance:init()
    return instance
end)

if success then
    myPJLinkDisplayController = controller
    PJLinkDisplayControllerInstance = controller
    print("PJLink DisplayController initialized - " .. controller:getDisplayCount() .. " displays")
else
    print("ERROR: Failed to create PJLink DisplayController: " .. tostring(controller))
end