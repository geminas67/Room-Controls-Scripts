--[[
  MTR Layer Recovery
  Author: Nikolas Smith, Q-SYS
  Version: 1.2 | Date: 2026-10-16
  Firmware Req: 10.4
  Recovers MTR UCI layer sync after statusMTR reconnects by briefly inverting
  each uciLayerController visibility pin, then restoring it, when status is OK.
]]

-------------------[ Configuration ]-------------------

pulseLen   = 0.2
stateDebug = true

-------------------[ Constant Tables ]-------------------

layerIndex    = {}
queueRecovery = nil

-------------------[ Components ]-------------------

statusMTR          = Component.New("statusMTR")
uciLayerController = Component.New("uciLayerController")

-------------------[ Functions ]-------------------

-------------------[ Debug ]-------------------

function debugMsg(str)
  if stateDebug then print("[MTRLayerRecovery] " .. str) end
end

function onOff(state)
  return state and "on" or "off"
end

-------------------[ Discovery ]-------------------

function buildLayerIndex()
  layerIndex = {}

  local controls = Component.GetControls("uciLayerController")
  for _, ctl in ipairs(controls) do
    if ctl.Name then
      local layerName = string.match(ctl.Name, "^(.-)%.visibility$")
      if layerName then layerIndex[#layerIndex + 1] = layerName end
    end
  end
  table.sort(layerIndex) -- sort alphabetically
  debugMsg("Discovered " .. tostring(#layerIndex) .. " layer(s)")
  for _, name in ipairs(layerIndex) do
    debugMsg("Layer: " .. name)
  end
end

-------------------[ Recovery ]-------------------

function pulseLayer(i)
  local entry = queueRecovery[i]
  if not entry then
    queueRecovery = nil
    debugMsg("Recovery complete")
    return
  end

  entry.pin.Boolean = not entry.visible
  debugMsg("Pulse " .. onOff(not entry.visible) .. ": " .. entry.name)

  Timer.CallAfter(function()
    entry.pin.Boolean = entry.visible
    debugMsg("Restore " .. onOff(entry.visible) .. ": " .. entry.name)
    pulseLayer(i + 1)
  end, pulseLen)
end

function reconcileMTRLayers()
  if statusMTR["status"].String ~= "OK" then return end

  if queueRecovery then
    debugMsg("Recovery already in progress, ignored")
    return
  end

  queueRecovery = {}
  for _, name in ipairs(layerIndex) do
    local pin = uciLayerController[name .. ".visibility"]
    if pin then
      queueRecovery[#queueRecovery + 1] = {
        name = name,
        pin = pin,
        visible = pin.Boolean
      }
    else
      debugMsg("WARNING: no control " .. name .. ".visibility")
    end
  end

  debugMsg("Starting reconcilation for " .. tostring(#queueRecovery) .. " layer(s)")
  pulseLayer(1)
end

-------------------[ Init ]-------------------

function funcInit()
  buildLayerIndex()
  reconcileMTRLayers()
end

-------------------[ Event Handlers ]-------------------

statusMTR["status"].EventHandler = reconcileMTRLayers

-------------------[ Always Run ]-------------------

funcInit()
