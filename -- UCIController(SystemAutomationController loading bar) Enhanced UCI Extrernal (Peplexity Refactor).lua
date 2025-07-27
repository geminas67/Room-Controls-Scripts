--[[
  UCIController (Refactored Modular Q-SYS Version)
  Author: Nikolas Smith, Q-SYS
  Date: 2025-07-24
  Version: 2.0
  Notes:
    - Modular, event-driven design
    - Safe wrappers for all dynamic access
    - Compatible with SystemAutomationController example integration
]]--

------------------------------------------
-- Safe Control/Variable/Component Access
------------------------------------------
local function safeControl(name, property)
    local ctrl = Controls and Controls[name]
    if not ctrl then return nil end
    if property then
      return ctrl[property] ~= nil and ctrl[property] or nil
    end
    return ctrl
  end
  
  local function safeVariable(name)
    return Uci.Variables and Uci.Variables[name] or nil
  end
  
  local function safeComponent(name)
    local hasComponent = name and name ~= ""
    if not hasComponent then return nil end
    local success, comp = pcall(function() return Component.New(name) end)
    if success then return comp else return nil end
  end
  
  ------------------------------------------
  -- VideoSwitcherIntegration Module
  ------------------------------------------
  local VideoSwitcherIntegration = {}
  VideoSwitcherIntegration.__index = VideoSwitcherIntegration
  
  VideoSwitcherIntegration.Types = {
    NV32 = {
      name = "NV32",
      componentType = "streamer_hdmi_switcher",
      variableNames = {"devNV32", "codenameNV32", "varNV32", "nv32Device", "nv32Component"},
      routingMethod = "hdmi.out.1.select.index",
      defaultMapping = {[7]=5, [8]=4, [9]=6}
    },
    ExtronDXP = {
      name = "Extron DXP",
      componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
      variableNames = {"devExtronDXP", "codenameExtronDXP", "varExtronDXP", "extronDXPDevice", "extronDXPComponent"},
      routingMethod = "output.1",
      defaultMapping = {[7]=2, [8]=4, [9]=1}
    },
    Generic = {
      name = "Generic",
      componentType = nil,
      variableNames = {"devVideoSwitcher", "codenameVideoSwitcher", "varVideoSwitcher"},
      routingMethod = "output.1",
      defaultMapping = {[7]=1, [8]=2, [9]=3}
    }
  }
  
  function VideoSwitcherIntegration.new()
    local self = setmetatable({}, VideoSwitcherIntegration)
    self.type = nil
    self.component = nil
    self.config = nil
    self.mapping = {}
    self.enabled = false
    self.cache = {timestamp = 0, duration = 30, data = nil}
    return self
  end
  
  function VideoSwitcherIntegration:discover()
    local now = Timer.Now()
    if self.cache.data and (now - self.cache.timestamp) < self.cache.duration then
      return self.cache.data
    end
    local allComps = Component.GetComponents()
    local byType = {}
    for _, comp in ipairs(allComps) do
      byType[comp.Type] = byType[comp.Type] or {}
      table.insert(byType[comp.Type], comp.Name)
    end
    local discovered = {}
    for key, config in pairs(VideoSwitcherIntegration.Types) do
      if config.componentType and byType[config.componentType] then
        discovered[key] = byType[config.componentType]
      end
    end
    self.cache.data = discovered
    self.cache.timestamp = now
    return discovered
  end
  
  function VideoSwitcherIntegration:autoDetect()
    local disc = self:discover()
    for key, config in pairs(VideoSwitcherIntegration.Types) do
      for _, var in ipairs(config.variableNames) do
        local ctrl = safeControl(var)
        if ctrl and ctrl.String and ctrl.String ~= "" then
          self.type, self.config = key, VideoSwitcherIntegration.Types[key]
          self.component = safeComponent(ctrl.String)
          return true
        end
      end
    end
    for key, comps in pairs(disc) do
      if comps and #comps > 0 then
        self.type, self.config = key, VideoSwitcherIntegration.Types[key]
        self.component = safeComponent(comps[1])
        return true
      end
    end
    self.type, self.config, self.component = nil, nil, nil
    return false
  end
  
  function VideoSwitcherIntegration:initialize()
    if not self:autoDetect() or not self.component then
      self.enabled = false
      return false
    end
    self.mapping = self.config.defaultMapping
    self.enabled = true
    return true
  end
  
  function VideoSwitcherIntegration:switchToInput(inputNumber)
    if not self.enabled or not self.component or not self.config then return false end
    local method = self.config.routingMethod
    local ok = false
    if self.type == "NV32" then
      ok = pcall(function()
        self.component[method].Value = inputNumber
        return self.component[method].Value == inputNumber
      end)
    elseif self.type == "ExtronDXP" then
      ok = pcall(function()
        self.component[method].String = tostring(inputNumber)
        return self.component[method].String == tostring(inputNumber)
      end)
    else
      ok = pcall(function()
        self.component[method].Value = inputNumber
        return self.component[method].Value == inputNumber
      end) or pcall(function()
        self.component[method].String = tostring(inputNumber)
        return self.component[method].String == tostring(inputNumber)
      end)
    end
    return ok
  end
  
  function VideoSwitcherIntegration:setupUCIButtonEvents(mapping, buttonNameFn)
    if not self.enabled then return end
    for uciButton, inputNumber in pairs(mapping) do
      local name = buttonNameFn(uciButton)
      local btn = safeControl(name)
      if btn then
        btn.EventHandler = function(ctrl)
          if ctrl.Boolean then
            self:switchToInput(inputNumber)
          end
        end
      end
    end
  end
  
  ------------------------------------------
  -- UCIController Class
  ------------------------------------------
  UCIController = {}
  UCIController.__index = UCIController
  
  -- Construction helpers
  local function getButtonName(idx) return ("btnNav%02d"):format(idx) end
  local function getLegendName(idx) return ("txtNav%02d"):format(idx) end
  
  function UCIController.new(uciPage, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices, hiddenHelpIndices)
    local self = setmetatable({}, UCIController)
    self.uciPage = uciPage
    self.layerStates = {}
    self.activeLayer = defaultActiveLayer or 3
    self.defaultActiveLayer = defaultActiveLayer or 3
    self.activeRoutingLayer = defaultRoutingLayer or 1
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.hiddenHelpIndices = hiddenHelpIndices or {}
    self.isInitialized = false
  
    -- Video Switcher (auto-detect & setup)
    self.videoSwitcher = VideoSwitcherIntegration.new()
    self.videoSwitcher:initialize()
  
    -- Controls (populate arrays safely)
    self.arrbtnNavs = {}
    for i = 1, 12 do self.arrbtnNavs[i] = safeControl(getButtonName(i)) end
    self.arrUCILegends = {}
    for i = 1, 12 do self.arrUCILegends[i] = safeControl(getLegendName(i)) end
  
    -- Routing
    self.routingButtons = {}
    for i = 1, 5 do self.routingButtons[i] = safeControl("btnRouting0"..i) end
    self.routingLayers = {
      "R01-Routing-Lobby", "R02-Routing-WTerrace",
      "R03-Routing-NTerraceWall", "R04-Routing-Garden", "R05-Routing-NTerraceFloor"
    }
  
    -- Room controls component (try multiple heuristics)
    self.roomControlsComponent = self:findRoomControlsComponent()
  
    -- Register event handlers
    self:registerEvents()
  
    -- Setup video switcher UCI button events (if available)
    if self.videoSwitcher.enabled then
      self.videoSwitcher:setupUCIButtonEvents(
        self.videoSwitcher.mapping, getButtonName
      )
    end
  
    return self
  end
  
  function UCIController:findRoomControlsComponent()
    local var = safeVariable("compRoomControls")
    if var and var.String then
      local comp = safeComponent(var.String)
      if comp then return comp end
    end
    -- Fallback naming convention
    local pageName = (self.uciPage or ""):gsub("%s+", "")
    if pageName ~= "" then
      local comp = safeComponent("compRoomControls" .. pageName)
      if comp then return comp end
    end
    return nil
  end
  
  function UCIController:registerEvents()
    -- Example: Routing button event registration
    for idx, btn in ipairs(self.routingButtons) do
      if btn then
        btn.EventHandler = function(ctrl)
          if ctrl.Boolean then
            self:switchRoutingLayer(idx)
          end
        end
      end
    end
    -- Add other event handlers as needed (nav, help, etc.)
  end
  
  function UCIController:switchRoutingLayer(idx)
    if not self.routingLayers[idx] then return end
    self.activeRoutingLayer = idx
    self:updateRoutingLayerVisibility()
  end
  
  function UCIController:updateRoutingLayerVisibility()
    -- Hide all layers
    for _, layer in ipairs(self.routingLayers) do
      self:setLayerVisibility(layer, false)
    end
    -- Show active
    local lay = self.routingLayers[self.activeRoutingLayer]
    if lay then self:setLayerVisibility(lay, true, "fade") end
  end
  
  function UCIController:setLayerVisibility(layer, visible, transition)
    local trans = transition or "none"
    local ok = pcall(function()
      Uci.SetLayerVisibility(self.uciPage, layer, visible, trans)
    end)
    self.layerStates[layer] = visible
  end
  
  function UCIController:powerOnRoom()
    -- Try component first
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
      local ok, res = pcall(function()
        self.roomControlsComponent["btnSystemOnOff"].Boolean = true
        return self.roomControlsComponent["btnSystemOnOff"].Boolean == true
      end)
      if ok and res then return true end
    end
    -- Fallback: direct control
    if Controls and Controls.btnSystemOnOff then
      Controls.btnSystemOnOff.Boolean = true
      return Controls.btnSystemOnOff.Boolean == true
    end
    return false
  end
  
  function UCIController:powerOffRoom()
    -- Try component first
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
      local ok, res = pcall(function()
        self.roomControlsComponent["btnSystemOnOff"].Boolean = false
        return self.roomControlsComponent["btnSystemOnOff"].Boolean == false
      end)
      if ok and res then return true end
    end
    if Controls and Controls.btnSystemOnOff then
      Controls.btnSystemOnOff.Boolean = false
      return Controls.btnSystemOnOff.Boolean == false
    end
    return false
  end
  
  function UCIController:getRoomAutomationTiming(isOn)
    if self.roomControlsComponent then
      local field = isOn and "warmupTime" or "cooldownTime"
      local val = self.roomControlsComponent[field]
      if val and val.Value then return val.Value end
    end
    local fallback = isOn and "timeProgressWarming" or "timeProgressCooling"
    local var = safeVariable(fallback)
    return var and tonumber(var.String) or (isOn and 10 or 5)
  end
  
  -- Add more utility/state/UI methods as needed (see legacy script for full features)
  
  ---------------------------------------------------
  -- Initialization for Q-SYS Processor Integration
  ---------------------------------------------------
  
  -- Create and configure the UCI Controller
  local uciPage = "UCI Main Page"
  local ctrl = UCIController.new(uciPage, 1, 3, {}, {})
  
  -- Example layer and routing state sync (early boot)
  ctrl:updateRoutingLayerVisibility()
  
  -- Optionally, add SystemAutomationController/other integrations here.
  
  -- End of Script
  