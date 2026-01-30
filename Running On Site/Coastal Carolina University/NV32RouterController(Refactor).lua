--[[
  NV32 Router Controller - Q-SYS Control Script
  Controls NV32 HDMI router with UCI integration and room controls
]]--

local controls = {
    devNV32 = Controls.devNV32,
    txtStatus = Controls.txtStatus,
    btnNV32Out01 = Controls.btnNV32Out01,
    btnNV32Out02 = Controls.btnNV32Out02,
    compRoomControls = Controls.compRoomControls
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

local function forEach(ctrls, fn)
    if not ctrls then return end
    local array = isArr(ctrls) and ctrls or { ctrls }
    for i, ctrl in ipairs(array) do fn(i, ctrl) end
end

local function normalizeControlArrays()
    for _, name in ipairs({'btnNV32Out01', 'btnNV32Out02'}) do
        local ctrl = controls[name]
        if ctrl and not isArr(ctrl) then controls[name] = {ctrl} end
    end
end

local function validateControls()
    for _, name in ipairs({"devNV32", "txtStatus", "btnNV32Out01"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

-------------------[ Controller ]-------------------
NV32RouterController = {}
NV32RouterController.__index = NV32RouterController

function NV32RouterController.new(roomName, config)
    if not validateControls() then return nil end
    normalizeControlArrays()
    
    local self = setmetatable({}, NV32RouterController)
    self.roomName = roomName or "NV32 Router"
    self.debugging = (config and config.debugging) or true
    self.enableOutput2 = (config and config.enableOutput2) or false
    self.clearString = "[Clear]"
    self.componentTypes = {
        nv32Router = "streamer_hdmi_switcher",
        roomControls = "device_controller_script"
    }
    self.components = { nv32Router = nil, roomControls = nil, invalid = {} }
    self.state = { lastInput = {}, preFireAlarmInput = {}, fireAlarmActive = false }
    self.uci = { controller = nil, enabled = (config and config.uciIntegrationEnabled) or false, lastLayer = nil }
    self.inputs = { Graphic1 = 1, Graphic2 = 2, Graphic3 = 3, HDMI1 = 4, HDMI2 = 5, HDMI3 = 6, AV1 = 7, AV2 = 8, AV3 = 9 }
    self.outputs = { Output01 = 1, Output02 = 2 }
    self.uciInputs = { self.inputs.AV1, self.inputs.AV2, self.inputs.AV3, self.inputs.Graphic1, self.inputs.Graphic2 }
    self.uciLayerToInput = { [7] = self.uciInputs[2], [8] = self.uciInputs[1], [9] = self.uciInputs[3] }
    self.timers = { uciMonitor = Timer.New() }
    
    return self
end

function NV32RouterController:debugPrint(str)
    if self.debugging then print("["..self.roomName.."] "..str) end
end

function NV32RouterController:safeAccess(component, control, action, value)
    local success, result = pcall(function()
        if not component or not component[control] then return false end
        if action == "set" then component[control].Value = value; return true end
        if action == "trigger" then component[control]:Trigger(); return true end
        if action == "get" then return component[control].Value end
        if action == "getBoolean" then return component[control].Boolean end
    end)
    return success and result or false
end

-------------------[ UCI Integration ]-------------------
function NV32RouterController:setUCIController(uciController)
    if not uciController then 
        self:debugPrint("Invalid UCI Controller reference provided")
        return false 
    end
    self.uci.controller = uciController
    if self.uci.enabled then self:startUCIMonitoring() end
    self:debugPrint("UCI Controller reference set - Integration " .. (self.uci.enabled and "ENABLED" or "DISABLED"))
    return true
end

function NV32RouterController:startUCIMonitoring()
    if not self.uci.controller then 
        self:debugPrint("No UCI Controller available for monitoring")
        return 
    end
    self.timers.uciMonitor.EventHandler = function()
        self:checkUCILayerChange()
        self.timers.uciMonitor:Start(0.1)
    end
    self.timers.uciMonitor:Start(0.1)
    self:debugPrint("UCI layer monitoring started (polling every 100ms)")
end

function NV32RouterController:checkUCILayerChange()
    if not self.uci.controller or not self.uci.enabled then return end
    local currentLayer = self.uci.controller.varActiveLayer
    if self.uci.lastLayer ~= currentLayer then
        self:debugPrint("UCI Layer changed: " .. tostring(self.uci.lastLayer) .. " → " .. tostring(currentLayer))
        self.uci.lastLayer = currentLayer
        if self.uciLayerToInput[currentLayer] then
            local targetInput = self.uciLayerToInput[currentLayer]
            self:debugPrint("UCI Layer " .. currentLayer .. " triggers input switch to " .. targetInput)
            self:setRoute(targetInput, self.outputs.Output01, "UCI Layer " .. currentLayer)
        end
    end
end

function NV32RouterController:setupDirectUCIButtonMonitoring()
    local uciButtons = { [7] = Controls.btnNav07, [8] = Controls.btnNav08, [9] = Controls.btnNav09 }
    local buttonCount = 0
    for layer, button in pairs(uciButtons) do
        if button then
            bind(button, function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    self:debugPrint("UCI Button " .. layer .. " pressed")
                    self:setRoute(self.uciLayerToInput[layer], self.outputs.Output01, "UCI Button " .. layer)
                end
            end)
            buttonCount = buttonCount + 1
            self:debugPrint("Direct monitoring set up for UCI button layer " .. layer)
        end
    end
    if buttonCount > 0 then
        self:debugPrint("UCI direct button monitoring configured for " .. buttonCount .. " buttons")
    end
end

function NV32RouterController:onUCILayerChange(layerChangeInfo)
    if not self.uci.enabled then 
        self:debugPrint("UCI integration disabled, ignoring layer change")
        return 
    end
    if not self.uciLayerToInput[layerChangeInfo.currentLayer] then 
        self:debugPrint("UCI Layer " .. layerChangeInfo.currentLayer .. " has no input mapping")
        return 
    end
    self:debugPrint("UCI Layer change notification: Layer " .. layerChangeInfo.currentLayer .. " (" .. (layerChangeInfo.layerName or "Unknown") .. ")")
    self:setRoute(self.uciLayerToInput[layerChangeInfo.currentLayer], self.outputs.Output01, "UCI Notification")
end

-------------------[ Component Management ]-------------------
function NV32RouterController:setComponent(ctrl, componentType)
    local name = ctrl and ctrl.String
    if not name or name == "" or name == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self.components.invalid[componentType] = false
        self:checkStatus()
        self:debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    if #Component.GetControls(comp) < 1 then
        if ctrl then ctrl.String = "[Invalid]"; ctrl.Color = "pink" end
        self.components.invalid[componentType] = true
        self:checkStatus()
        self:debugPrint("ERROR: " .. componentType .. " component '" .. name .. "' is invalid")
        return nil
    end
    if ctrl then ctrl.Color = "white" end
    self.components.invalid[componentType] = false
    self:checkStatus()
    self:debugPrint("Set " .. componentType .. " component: " .. name)
    return comp
end

function NV32RouterController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

function NV32RouterController:getComponentNames()
    local names = { NV32Names = {}, RoomControlsNames = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.nv32Router then
            table.insert(names.NV32Names, comp.Name)
            self:debugPrint("Discovered NV32 Router: " .. comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and comp.Name:match("^compRoomControls") then
            table.insert(names.RoomControlsNames, comp.Name)
            self:debugPrint("Discovered Room Controls: " .. comp.Name)
        end
    end
    for _, list in pairs(names) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    if controls.devNV32 then controls.devNV32.Choices = names.NV32Names end
    if controls.compRoomControls then controls.compRoomControls.Choices = names.RoomControlsNames end
    self:debugPrint("Component discovery complete - " .. #names.NV32Names .. " NV32 routers, " .. #names.RoomControlsNames .. " Room Controls found")
end

function NV32RouterController:setNV32RouterComponent()
    local router = self.components.nv32Router
    if router then
        if router["hdmi.out.1.select.index"] then router["hdmi.out.1.select.index"].EventHandler = nil end
        if router["hdmi.out.2.select.index"] then router["hdmi.out.2.select.index"].EventHandler = nil end
        self:debugPrint("Cleanup completed - switching NV32 devices")
    end
    
    self.components.nv32Router = self:setComponent(controls.devNV32, "NV32-H")
    router = self.components.nv32Router
    if not router then return end
    
    if router["hdmi.out.1.select.index"] then
        router["hdmi.out.1.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(controls.btnNV32Out01) do
                setProp(btn, "Boolean", (self.uciInputs[i] == ctl.Value))
            end
            self:debugPrint("NV32 Feedback: Output 1 → Input " .. ctl.Value)
        end
        self:debugPrint("Registered feedback handler for Output 1")
    end
    
    if router["hdmi.out.2.select.index"] and self.enableOutput2 and controls.btnNV32Out02 then
        router["hdmi.out.2.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(controls.btnNV32Out02) do
                setProp(btn, "Boolean", (self.uciInputs[i] == ctl.Value))
            end
            self:debugPrint("NV32 Feedback: Output 2 → Input " .. ctl.Value)
        end
        self:debugPrint("Registered feedback handler for Output 2")
    end
end

function NV32RouterController:setRoomControlsComponent()
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    local comp = self.components.roomControls
    if not comp then return end
    
    if comp["ledSystemPower"] then
        comp["ledSystemPower"].EventHandler = function(ctl)
            local targetInput = ctl.Boolean and self.uciInputs[1] or self.uciInputs[4]
            self:debugPrint("System Power " .. (ctl.Boolean and "ON" or "OFF") .. " - switching to input " .. targetInput)
            self:setRoute(targetInput, self.outputs.Output01, "System Power")
            if self.enableOutput2 then self:setRoute(targetInput, self.outputs.Output02, "System Power") end
        end
        self:debugPrint("Registered System Power handler")
    end
    
    if comp["ledFireAlarm"] then
        comp["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean and not self.state.fireAlarmActive then
                self:debugPrint("Fire Alarm ACTIVATED - storing current inputs and switching to alarm input")
                self.state.preFireAlarmInput[self.outputs.Output01] = self.state.lastInput[self.outputs.Output01]
                if self.enableOutput2 then
                    self.state.preFireAlarmInput[self.outputs.Output02] = self.state.lastInput[self.outputs.Output02]
                end
                self.state.fireAlarmActive = true
                self:setRoute(self.uciInputs[5], self.outputs.Output01, "Fire Alarm")
                if self.enableOutput2 then self:setRoute(self.uciInputs[5], self.outputs.Output02, "Fire Alarm") end
            elseif not ctl.Boolean and self.state.fireAlarmActive then
                self:debugPrint("Fire Alarm CLEARED - restoring previous inputs")
                self.state.fireAlarmActive = false
                if comp["ledSystemPower"] and comp["ledSystemPower"].Boolean then
                    self:setRoute(self.state.preFireAlarmInput[self.outputs.Output01] or self.uciInputs[1], self.outputs.Output01, "Fire Alarm Clear")
                    if self.enableOutput2 then
                        self:setRoute(self.state.preFireAlarmInput[self.outputs.Output02] or self.uciInputs[1], self.outputs.Output02, "Fire Alarm Clear")
                    end
                end
                self.state.preFireAlarmInput = {}
            end
        end
        self:debugPrint("Registered Fire Alarm handler")
    end
end

-------------------[ Routing Methods ]-------------------
function NV32RouterController:setRoute(input, output, source)
    if output == self.outputs.Output02 and not self.enableOutput2 then 
        self:debugPrint("Output 2 disabled, skipping route")
        return false 
    end
    local router = self.components.nv32Router
    if not router then 
        self:debugPrint("No NV32 router available for routing")
        return false 
    end
    local outputControl = router["hdmi.out."..tostring(output)..".select.index"]
    if not outputControl then 
        self:debugPrint("Invalid output control for output " .. tostring(output))
        return false 
    end
    if outputControl.Value == input then 
        self:debugPrint("Output " .. output .. " already set to input " .. input)
        return false 
    end
    outputControl.Value = input
    self.state.lastInput[output] = input
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    self:debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    return true
end

-------------------[ Event Registration ]-------------------
function NV32RouterController:registerEvents()
    bind(controls.devNV32, function() self:setNV32RouterComponent() end)
    self:debugPrint("Registered event handler for devNV32")
    
    bind(controls.compRoomControls, function() self:setRoomControlsComponent() end)
    self:debugPrint("Registered event handler for compRoomControls")
    
    bindArray(controls.btnNV32Out01, function(i) 
        self:debugPrint("Output 1 Button " .. i .. " pressed")
        self:setRoute(self.uciInputs[i], self.outputs.Output01, "User Button") 
    end)
    self:debugPrint("Registered " .. #controls.btnNV32Out01 .. " button handlers for Output 1")
    
    if self.enableOutput2 then
        bindArray(controls.btnNV32Out02, function(i) 
            self:debugPrint("Output 2 Button " .. i .. " pressed")
            self:setRoute(self.uciInputs[i], self.outputs.Output02, "User Button") 
        end)
        self:debugPrint("Registered " .. #controls.btnNV32Out02 .. " button handlers for Output 2")
    end
    
    self:setupDirectUCIButtonMonitoring()
end

function NV32RouterController:init()
    self:debugPrint("=== Initialization Started ===")
    self:debugPrint("Configuration: debugging=" .. tostring(self.debugging) .. ", enableOutput2=" .. tostring(self.enableOutput2) .. ", uciEnabled=" .. tostring(self.uci.enabled))
    
    self:getComponentNames()
    self:setNV32RouterComponent()
    self:setRoomControlsComponent()
    
    if self.components.nv32Router then
        self:debugPrint("Setting default input selection to input " .. self.uciInputs[1])
        self:setRoute(self.uciInputs[1], self.outputs.Output01, "Initialization")
        if self.enableOutput2 then 
            self:setRoute(self.uciInputs[1], self.outputs.Output02, "Initialization") 
        end
    else
        self:debugPrint("WARNING: No NV32 router component available - skipping default input selection")
    end
    
    self:debugPrint("=== Initialization Complete ===")
    self:debugPrint("Active Outputs: " .. (self.enableOutput2 and "Output 1 & Output 2" or "Output 1 only"))
    self:debugPrint("Ready for operation")
end


-------------------[ Factory & Initialization ]-------------------
local function getRoomName()
    if controls.compRoomControls and controls.compRoomControls.String ~= "" and controls.compRoomControls.String ~= "[Clear]" then
        local comp = Component.New(controls.compRoomControls.String)
        if comp and comp["roomName"] and comp["roomName"].String ~= "" then
            return "["..comp["roomName"].String.."]"
        end
    end
    return "[NV32 Router]"
end

local success, controller = pcall(function()
    local instance = NV32RouterController.new(getRoomName(), { debugging = true, uciIntegrationEnabled = false, enableOutput2 = false })
    if not instance then error("Validation failed") end
    instance:registerEvents()
    instance:init()
    return instance
end)

if success then
    myNV32RouterController = controller
    NV32RouterControllerInstance = controller
    print("NV32 Router Controller initialized")
else
    print("ERROR: Failed to create NV32 Router Controller: " .. tostring(controller))
end