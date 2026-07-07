--[[
  Control & UCI Fundamentals (Q-Sys Course) - Refactored
  Layer navigation (Room / Displays / Cameras), legend binding, NV32 routing
  with friendly names, list box outputs, and laptop-active routing.
]]--

-------------------[ Controls ]-------------------
local controls = {
  btnNavRoom = Controls.btnNavRoom,
  btnNavDisplays = Controls.btnNavDisplays,
  btnNavCameras = Controls.btnNavCameras,
  pinLEDUSB = Controls.pinLEDUSB,
  listOut01 = Controls.listOut01,
  listOut02 = Controls.listOut02,
  pinLEDLaptop01Active = Controls.pinLEDLaptop01Active,
  pinLEDLaptop02Active = Controls.pinLEDLaptop02Active,
  -- UCI Variables
  navBtnRoomLegend = Uci.Variables.navBtnRoomLegend,
  navBtnDisplaysLegend = Uci.Variables.navBtnDisplaysLegend,
  navBtnCamerasLegend = Uci.Variables.navBtnCamerasLegend,
  varNV32CodeName = Uci.Variables.varNV32CodeName,
  friendlyHDMI01 = Uci.Variables.friendlyHDMI01,
  friendlyHDMI02 = Uci.Variables.friendlyHDMI02,
  friendlyHDMI03 = Uci.Variables.friendlyHDMI03,
  friendlyGraphic01 = Uci.Variables.friendlyGraphic01,
  friendlyGraphic02 = Uci.Variables.friendlyGraphic02,
  friendlyGraphic03 = Uci.Variables.friendlyGraphic03,
}

-------------------[ Layer constants ]-------------------
local kLayerRoom = 1
local kLayerDisplays = 2
local kLayerCameras = 3

local kDisplay01 = 1
local kDisplay02 = 2
local kLaptop01 = 1
local kLaptop02 = 2

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

local function validateControls()
  local required = {
    "btnNavRoom", "btnNavDisplays", "btnNavCameras",
    "listOut01", "listOut02", "varNV32CodeName",
  }
  for _, name in ipairs(required) do
    if not controls[name] then
      print("ERROR: Missing required control: " .. name)
      return false
    end
  end
  return true
end

-------------------[ Controller ]-------------------
UCIController = {}
UCIController.__index = UCIController

function UCIController.new(roomName, config)
  if not validateControls() then return nil end

  local self = setmetatable({}, UCIController)
  self.roomName = roomName or "[Default]"
  self.debugging = (config and config.debugging) ~= false

  self.state = {
    activeLayer = kLayerRoom,
  }
  self.components = {
    nv32 = nil,
    listBox = { controls.listOut01, controls.listOut02 },
    friendlyNames = nil,
    babelFish = nil,
  }

  return self
end

function UCIController:debugPrint(str)
  if self.debugging then print("[" .. self.roomName .. "] " .. str) end
end

-------------------[ Layer & legend logic ]-------------------
function UCIController:updateLegends()
  setProp(controls.btnNavRoom, "Legend", controls.navBtnRoomLegend.String)
  setProp(controls.btnNavDisplays, "Legend", controls.navBtnDisplaysLegend.String)
  setProp(controls.btnNavCameras, "Legend", controls.navBtnCamerasLegend.String)
end

function UCIController:showCameraSublayer()
  local usbOn = controls.pinLEDUSB and controls.pinLEDUSB.Boolean
  Uci.SetLayerVisibility("classUCI", "C2_USB_Connected", usbOn, usbOn and "fade" or "none")
  Uci.SetLayerVisibility("classUCI", "C3_USB_Connected_NOT", not usbOn, not usbOn and "fade" or "none")
end

function UCIController:showLayer()
  Uci.SetLayerVisibility("classUCI", "A1_Room", false, "none")
  Uci.SetLayerVisibility("classUCI", "B1_Displays", false, "none")
  Uci.SetLayerVisibility("classUCI", "C1_Cameras", false, "none")
  Uci.SetLayerVisibility("classUCI", "C2_USB_Connected", false, "none")
  Uci.SetLayerVisibility("classUCI", "C3_USB_Connected_NOT", false, "none")
  Uci.SetLayerVisibility("classUCI", "Y1_Base Controls", true, "fade")
  Uci.SetLayerVisibility("classUCI", "Z1_BG", true, "fade")

  local layer = self.state.activeLayer
  if layer == kLayerRoom then
    Uci.SetLayerVisibility("classUCI", "A1_Room", true, "fade")
  elseif layer == kLayerDisplays then
    Uci.SetLayerVisibility("classUCI", "B1_Displays", true, "fade")
  elseif layer == kLayerCameras then
    Uci.SetLayerVisibility("classUCI", "C1_Cameras", true, "fade")
    self:showCameraSublayer()
  end
end

function UCIController:interlock()
  setProp(controls.btnNavRoom, "Boolean", false)
  setProp(controls.btnNavDisplays, "Boolean", false)
  setProp(controls.btnNavCameras, "Boolean", false)
  local layer = self.state.activeLayer
  if layer == kLayerRoom then setProp(controls.btnNavRoom, "Boolean", true)
  elseif layer == kLayerDisplays then setProp(controls.btnNavDisplays, "Boolean", true)
  elseif layer == kLayerCameras then setProp(controls.btnNavCameras, "Boolean", true)
  end
end

function UCIController:switchToLayer(layer, source)
  self.state.activeLayer = layer
  self:showLayer()
  self:interlock()
  local layerNames = { [kLayerRoom] = "Room", [kLayerDisplays] = "Displays", [kLayerCameras] = "Cameras" }
  self:debugPrint("UCI Layer: " .. (layerNames[layer] or "?") .. (source and " (Source: " .. source .. ")" or ""))
end

-------------------[ NV32 & routing ]-------------------
function UCIController:setChoices()
  local ctl = controls
  self.components.friendlyNames = {
    ctl.friendlyHDMI01.String,
    ctl.friendlyHDMI02.String,
    ctl.friendlyHDMI03.String,
    ctl.friendlyGraphic01.String,
  }
  self.components.babelFish = {}
  local tbl = self.components.babelFish
  tbl[ctl.friendlyHDMI01.String] = "HDMI 1"
  tbl[ctl.friendlyHDMI02.String] = "HDMI 2"
  tbl[ctl.friendlyHDMI03.String] = "HDMI 3"
  tbl[ctl.friendlyGraphic01.String] = "Graphic 1"
  tbl[ctl.friendlyGraphic02.String] = "Graphic 2"
  tbl[ctl.friendlyGraphic03.String] = "Graphic 3"
  tbl["HDMI 1"] = ctl.friendlyHDMI01.String
  tbl["HDMI 2"] = ctl.friendlyHDMI02.String
  tbl["HDMI 3"] = ctl.friendlyHDMI03.String
  tbl["Graphic 1"] = ctl.friendlyGraphic01.String
  tbl["Graphic 2"] = ctl.friendlyGraphic02.String
  tbl["Graphic 3"] = ctl.friendlyGraphic03.String

  for i, ctl in ipairs(self.components.listBox) do
    ctl.Choices = self.components.friendlyNames
  end
  self:debugPrint("Choices updated: " .. #self.components.friendlyNames .. " sources")
end

function UCIController:setNV32Component()
  local name = controls.varNV32CodeName and controls.varNV32CodeName.String
  if not name or name == "" then
    self:debugPrint("No NV32 component selected")
    self.components.nv32 = nil
    return
  end
  -- Cleanup old NV32 feedback handlers before switching
  local old = self.components.nv32
  if old then
    for i = 1, 2 do
      local path = "hdmi.out." .. i .. ".select.pretty.name"
      if old[path] then old[path].EventHandler = nil end
    end
    self:debugPrint("Cleaned up previous NV32 handlers")
  end
  local comp = Component.New(name)
  if #Component.GetControls(comp) < 1 then
    self:debugPrint("ERROR: NV32 component '" .. name .. "' is invalid")
    self.components.nv32 = nil
    return
  end
  self.components.nv32 = comp
  self:debugPrint("Set NV32 component: " .. name)
  -- Attach feedback handlers
  local babelFish = self.components.babelFish
  if not babelFish then return end
  for i = 1, 2 do
    local path = "hdmi.out." .. i .. ".select.pretty.name"
    if comp[path] then
      comp[path].EventHandler = function(ctl)
        local friendly = babelFish[ctl.String]
        if friendly and self.components.listBox[i] then
          setProp(self.components.listBox[i], "String", friendly)
        end
        self:debugPrint("NV32 Out " .. i .. " → " .. (ctl.String or "?") .. " (Source: device updated)")
      end
    end
  end
  self:debugPrint("Registered 2 NV32 feedback handlers")
end

function UCIController:videoSwitch(outNumber, inputString, source)
  local dev = self.components.nv32
  local babelFish = self.components.babelFish
  if not dev or not babelFish then return end
  local pretty = babelFish[inputString]
  if not pretty then return end
  local path = "hdmi.out." .. outNumber .. ".select.pretty.name"
  if dev[path] then dev[path].String = pretty end
  self:debugPrint("Routed Out " .. outNumber .. " → " .. (pretty or inputString) .. (source and " (Source: " .. source .. ")" or ""))
end

-------------------[ Event registration ]-------------------
function UCIController:registerEvents()
  -- Nav buttons
  bind(controls.btnNavRoom, function()
    self:switchToLayer(kLayerRoom, "User: Room")
  end)
  bind(controls.btnNavDisplays, function()
    self:switchToLayer(kLayerDisplays, "User: Displays")
  end)
  bind(controls.btnNavCameras, function()
    self:switchToLayer(kLayerCameras, "User: Cameras")
  end)
  self:debugPrint("Registered 3 nav button handlers")

  -- USB LED: when true, switch to Cameras layer
  bind(controls.pinLEDUSB, function(ctl)
    if ctl.Boolean then self.state.activeLayer = kLayerCameras end
    self:showLayer()
    self:interlock()
    self:debugPrint("USB LED changed; layer refresh" .. (ctl.Boolean and " (Source: USB)" or ""))
  end)

  -- Legend variables
  bind(controls.navBtnRoomLegend, function() self:updateLegends() end)
  bind(controls.navBtnDisplaysLegend, function() self:updateLegends() end)
  bind(controls.navBtnCamerasLegend, function() self:updateLegends() end)
  self:debugPrint("Registered 3 legend handlers")

  -- NV32 code name
  bind(controls.varNV32CodeName, function() self:setNV32Component() end)

  -- Friendly name variables → rebuild choices
  local friendlyVars = {
    "friendlyHDMI01", "friendlyHDMI02", "friendlyHDMI03",
    "friendlyGraphic01", "friendlyGraphic02", "friendlyGraphic03",
  }
  for _, name in ipairs(friendlyVars) do
    bind(controls[name], function() self:setChoices() end)
  end
  self:debugPrint("Registered 6 friendly-name handlers")

  -- List box outputs: user selection → video switch
  for i, ctl in ipairs(self.components.listBox) do
    bind(ctl, function()
      self:videoSwitch(i, ctl.String, "user interaction")
    end)
  end
  self:debugPrint("Registered " .. #self.components.listBox .. " list box handlers")

  -- Laptop-active pins: route both displays to that laptop source
  bind(controls.pinLEDLaptop01Active, function(ctl)
    if not ctl.Boolean then return end
    local names = self.components.friendlyNames
    if not names then return end
    self:videoSwitch(kDisplay01, names[kLaptop01], "Laptop 1 active")
    self:videoSwitch(kDisplay02, names[kLaptop01], "Laptop 1 active")
  end)
  bind(controls.pinLEDLaptop02Active, function(ctl)
    if not ctl.Boolean then return end
    local names = self.components.friendlyNames
    if not names then return end
    self:videoSwitch(kDisplay01, names[kLaptop02], "Laptop 2 active")
    self:videoSwitch(kDisplay02, names[kLaptop02], "Laptop 2 active")
  end)
  self:debugPrint("Registered 2 laptop-active handlers")
end

-------------------[ Initialization ]-------------------
function UCIController:init()
  self:debugPrint("=== Initialization Started ===")
  self:debugPrint("Configuration: debugging=" .. tostring(self.debugging))

  self.state.activeLayer = kLayerRoom
  self:setChoices()
  self:setNV32Component()
  self:showLayer()
  self:interlock()
  self:updateLegends()

  self:debugPrint("=== Initialization Complete ===")
  self:debugPrint("UCI Initialized")
end

-------------------[ Factory & startup ]-------------------
local function getRoomName()
  -- Original script has no room name control; use fixed prefix for debug
  return "UCI"
end

local success, controller = pcall(function()
  local instance = UCIController.new(getRoomName(), { debugging = true })
  if not instance then error("Validation failed") end
  instance:registerEvents()
  instance:init()
  return instance
end)

if success then
  myController = controller
  UCIControllerInstance = controller
  print("UCI Controller initialized")
else
  print("ERROR: Failed to create UCI controller: " .. tostring(controller))
end
