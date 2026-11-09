--[[
  UCI Controller Basic - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.1 | Date: 2026-11-05
  Firmware Req: 10.4 (GetLayerVisibility per layer in applyDesired)

  Training-room UCI: pinpad Start→Main, exit Main→Start, three nav content layers.
  Same visibility engine as workplace UCI (buildDesired → applyDesired), without
  power, routing, help, or source overlays.
]]--

----[ Configuration ]----
-- NOTE: Remove instances in applyDesired() if used as UCI Script
uciName   = "Training" -- used for debugPrint()
pageMain  = "Main"
pageStart = "Start"

kLayer = {
  None         = 0,  -- Base only (no content layer)
  Cameras      = 1,
  Microphones  = 2,
  Projection   = 3,
}

kLayerName = {}
for name, idx in pairs(kLayer) do kLayerName[idx] = name end

layersBase    = {"Base"}
layersContent = {"Cameras", "Microphones", "Projection"}

layerConfig = {
  [kLayer.None]        = {},
  [kLayer.Cameras]     = { show = {"Cameras"} },
  [kLayer.Microphones] = { show = {"Microphones"} },
  [kLayer.Projection]  = { show = {"Projection"} },
}

compPinpad = Component.New("pinpadTraining")
compExit   = Component.New("btnExit")
compStatus = Component.New("statusTSC-101-G3")

----[ Constant Tables ]----

btnNav = Controls.btnNav

----[ Constants ]----

stateDebug    = true
layerDefault  = kLayer.None
state = { activeLayer = layerDefault }

----[ Functions ]----

----[ Setup ]----

function debugPrint(str)
  if stateDebug then print("["..uciName.."] "..str) end
end

----[ Visibility ]----

function want(desired, names, visible)
  if not names then return end
  if type(names) ~= "table" then names = {names} end
  for _, name in ipairs(names) do
    if name ~= "" then desired[name] = visible end
  end
end

function applyDesired(desired)
  for name, wantVis in pairs(desired) do
    local visOk, current = pcall(Uci.GetLayerVisibility, uciName, pageMain, name)
    if not visOk then
      print("Layer '"..name.."' not on page: "..tostring(current))
    elseif current ~= wantVis then
      local ok, err = pcall(Uci.SetLayerVisibility, uciName, pageMain, name, wantVis, wantVis and "fade" or "none")
      if ok then debugPrint("Layer '"..name.."' → "..tostring(wantVis))
      else print("Layer '"..name.."' error: "..tostring(err)) end
    end
  end
end

function buildDesired()
  local desired = {}
  want(desired, layersContent, false)
  want(desired, layersBase, true)

  local cfg = layerConfig[state.activeLayer]
  if cfg then want(desired, cfg.show, true) end

  return desired
end

function refreshLayers()
  applyDesired(buildDesired())
end

----[ Navigation ]----

function interlockNav()
  for i = 1, #btnNav do
    btnNav[i].Boolean = (i == state.activeLayer)
  end
end

function goToLayer(layerIndex, source)
  source = source or "Navigation"
  local prev = state.activeLayer
  state.activeLayer = layerIndex
  refreshLayers()
  interlockNav()
  debugPrint("Layer "..(kLayerName[prev] or prev).." → "..(kLayerName[layerIndex] or layerIndex).." (Source: "..source..")")
end

function setPage(pageName, source)
  compStatus["current.page"].String = pageName
  goToLayer(layerDefault, source)
  debugPrint("Page → ["..pageName.."] (Source: "..(source or "Page")..")")
end

----[ Event Handlers ]----

for i = 1, #btnNav do
  btnNav[i].EventHandler = function()
    goToLayer(i, "User Button")
  end
end

compPinpad["pin.match.0"].EventHandler = function(ctl)
  if not ctl.Boolean then return end
  setPage(pageMain, "Pin Matched")
end

compExit["trigger.1"].EventHandler = function()
  setPage(pageStart, "Exit")
end

----[ Always Run ]----

function funcInit()
  debugPrint("=== Initialization Started ===")
  setPage(pageStart, "Init")
  debugPrint("=== Initialization Complete ===")
end

funcInit()
