--[[
  HDMIPortController - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2025-11-08
  Version: 3.0
  Firmware Req: 10.0.0

  Controls decoder HDMI ports from UCI layer selectors and encoder hot plug.

]]--

-------------------[ Configuration ]-------------------

-- Maps each decoder to its encoder and UCI layer selectors
decoderConfig = {
  {
    name = "DEC-19",
    decoderComponent = "devDecoder19",
    encoderComponent = "devEncoder09",
    uciSelectors = {
      {component = "uciLayerSelectorEMC", control = "selector.5", name = "EMC Layer 6"},
      {component = "uciLayerSelectorRmA", control = "selector.4", name = "Rm-A Layer 5"},
    },
  },
  {
    name = "DEC-20",
    decoderComponent = "devDecoder20",
    encoderComponent = "devEncoder10",
    uciSelectors = {
      {component = "uciLayerSelectorEMC", control = "selector.7", name = "EMC Layer 8"},
      {component = "uciLayerSelectorRmB", control = "selector.4", name = "Rm-B Layer 5"},
    },
  },
}

-------------------[ Constant Tables ]-------------------

compDecoders = {}
compEncoders = {}
compUciSelectors = {}

-------------------[ Constants ]-------------------

stateDebug = true
roomName = "[HDMI Port Controller]"

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print("[" .. roomName .. "] " .. str)
end

-------------------[ HDMI Port ]-------------------

function setHdmiPort(decoderIndex, state)
  local config = decoderConfig[decoderIndex]
  if not config then
    debugMsg("ERROR: Invalid decoder index: " .. tostring(decoderIndex))
    return
  end

  local decoder = compDecoders[decoderIndex]
  if not decoder then
    debugMsg("ERROR: Decoder component not found for " .. config.name)
    return
  end

  local controlName = state and "HdmiPortOn" or "HdmiPortOff"
  local ctl = decoder[controlName]
  if not ctl then return end

  ctl:Trigger()
  debugMsg("HDMI Port " .. (state and "On" or "Off") .. " - " .. config.name)
end

function evaluateDecoderState(decoderIndex)
  local config = decoderConfig[decoderIndex]
  if not config then return end

  local encoder = compEncoders[decoderIndex]
  if not encoder then
    debugMsg("WARNING: Encoder component not found for " .. config.name)
    return
  end

  local hotPlugCtl = encoder.HotPlugDetect
  if not hotPlugCtl or not hotPlugCtl.Boolean then
    setHdmiPort(decoderIndex, false)
    return
  end

  local activeLayerName = nil
  for _, selectorConfig in ipairs(config.uciSelectors) do
    local selectorComponent = compUciSelectors[selectorConfig.component]
    local selectorCtl = selectorComponent and selectorComponent[selectorConfig.control]
    if selectorCtl and selectorCtl.Boolean then
      activeLayerName = selectorConfig.name
      break
    end
  end

  if activeLayerName then
    debugMsg("HDMI Port OR - " .. activeLayerName .. " Active and Hot Plug Detected")
    setHdmiPort(decoderIndex, true)
  else
    setHdmiPort(decoderIndex, false)
  end
end

-------------------[ Components ]-------------------

function setupComponents()
  debugMsg("Setting up components...")

  for i, config in ipairs(decoderConfig) do
    local decoder = Component.New(config.decoderComponent)
    if decoder then
      compDecoders[i] = decoder
      debugMsg("Decoder component set: " .. config.name)
    else
      debugMsg("ERROR: Failed to create decoder component: " .. config.decoderComponent)
    end

    local encoder = Component.New(config.encoderComponent)
    if encoder then
      compEncoders[i] = encoder
      debugMsg("Encoder component set: " .. config.encoderComponent)
    else
      debugMsg("ERROR: Failed to create encoder component: " .. config.encoderComponent)
    end

    for _, selectorConfig in ipairs(config.uciSelectors) do
      if not compUciSelectors[selectorConfig.component] then
        local selector = Component.New(selectorConfig.component)
        if selector then
          compUciSelectors[selectorConfig.component] = selector
          debugMsg("UCI Selector component set: " .. selectorConfig.component)
        else
          debugMsg("ERROR: Failed to create UCI selector component: " .. selectorConfig.component)
        end
      end
    end
  end

  debugMsg("Component setup complete")
end

function bindComponentHandlers()
  debugMsg("Registering event handlers...")

  for i, config in ipairs(decoderConfig) do
    local encoder = compEncoders[i]
    if encoder and encoder.HotPlugDetect then
      encoder.HotPlugDetect.EventHandler = function()
        debugMsg("Hot Plug Detect change for " .. config.name)
        evaluateDecoderState(i)
      end
    end

    for _, selectorConfig in ipairs(config.uciSelectors) do
      local selectorComponent = compUciSelectors[selectorConfig.component]
      local selectorCtl = selectorComponent and selectorComponent[selectorConfig.control]
      if selectorCtl then
        selectorCtl.EventHandler = function()
          debugMsg(selectorConfig.name .. " change")
          evaluateDecoderState(i)
        end
      end
    end
  end

  debugMsg("Event handler registration complete")
end

-------------------[ Event Handlers ]-------------------
-- Named component handlers are bound in bindComponentHandlers()

-------------------[ Always Run ]-------------------

function funcInit()
  debugMsg("Starting HDMI Port Controller initialization...")
  setupComponents()
  bindComponentHandlers()

  for i in ipairs(decoderConfig) do
    evaluateDecoderState(i)
  end

  debugMsg("HDMI Port Controller initialized successfully")
end

funcInit()
