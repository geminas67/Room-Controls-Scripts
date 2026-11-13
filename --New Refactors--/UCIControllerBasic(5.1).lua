--[[
  UCI Controller Basic - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.2 | Date: 2026-11-07
  Firmware Req: 10.4 (Uci.GetLayerVisibility)

  Training-room UCI: pinpad Start→Main, exit Main→Start, three nav content layers.

  Visibility: goToLayer() → setLayer() per layer. setLayer reads current state
  (GetLayerVisibility) and writes only on change: "fade" show, "none" hide.
  pcall surfaces missing or renamed layers to the console.
  Single input (activeLayer) — direct path, no buildDesired/applyDesired.
  Upgrade to buildDesired → applyDesired if 2+ inputs drive the same layers
  (power, call, HDMI, help overlays).
]]--


----[ Configuration ]----
-- NOTE: Remove uciName instances in setLayer() if used as UCI Script
uciName   = "Training" -- used for debugPrint()
pageMain  = "Main"
pageStart = "Start"

kLayer = {
  None         = 0,  -- Base only (no content layer)
  Cameras      = 1,
  Microphones  = 2,
  Projection   = 3,
}

layerBase   = {"Base"}
layerNav    = {"Cameras", "Microphones", "Projection"}

compPinpad = Component.New("pinpadTraining")
compStatus = Component.New("statusTSC-101-G3")

----[ Constant Tables ]----

btnNav = Controls.btnNav

----[ Constants ]----

stateDebug    = true
layerDefault  = kLayer.None
state = { activeLayer = layerDefault }

timerInactivity = Timer.New()
timeTouchInactivity = 120 -- seconds

----[ Functions ]----

----[ Setup ]----

function debugPrint(str)
  if stateDebug then print("["..uciName.."] "..str) end
end

-------------------[ Visibility ]-------------------

function setLayer(name, visible)
  local ok, current = pcall(Uci.GetLayerVisibility, uciName, pageMain, name)
  if not ok then print("Layer '"..name.."' not on page: "..tostring(current)) return end
  if current == visible then return end
  local okSet, err = pcall(Uci.SetLayerVisibility, uciName, pageMain, name, visible, visible and "fade" or "none")
  if okSet then debugPrint("Layer '"..name.."' → "..tostring(visible))
  else print("Layer '"..name.."' error: "..tostring(err)) end
end

----[ Navigation ]----

function interlockNav()
  for idx,btn in ipairs(btnNav) do
    btn.Boolean = (idx == state.activeLayer)
  end
end

function refreshLayers()
  for _, name in ipairs(layerBase) do setLayer(name, true) end
  for i, name in ipairs(layerNav) do setLayer(name, i == state.activeLayer) end
end

function goToLayer(layerIndex, source)
  local prev = state.activeLayer
  state.activeLayer = layerIndex
  interlockNav()
  refreshLayers()
  debugPrint("Layer "..(layerNav[prev] or "None").." → "..(layerNav[layerIndex] or "None").." (Source: "..(source or "Navigation")..")")
end

function setPage(pageName, source, navIndex)
  compStatus["current.page"].String = pageName
  goToLayer(navIndex or layerDefault, source or "Page")
  debugPrint("Page → ["..pageName.."] (Source: "..(source or "Page")..")")
  Timer.CallAfter( function()
    compPinpad['logout']:Trigger()
    debugPrint("Logout triggered")
  end, 1)
end

-------------------[ Room Controls ]-------------------

function resetTouchInactivityTimer()
  timerInactivity.Stop()
  if not Controls['ledTouchActivity'].Boolean then
    timerInactivity.Start(timeTouchInactivity)
  end
end

function onTouchInactivityTimeout()
  timerInactivity.Stop()
  setPage(pageStart, "Inactivity Timeout", layerDefault)
  debugPrint("Inactivity Timeout")
end

----[ Event Handlers ]----

for idx,btn in ipairs(btnNav) do
  btn.EventHandler = function()
    goToLayer(idx, "User Button")
  end
end

compPinpad["pin.match.0"].EventHandler = function(ctl)
  if not ctl.Boolean then return end
  setPage(pageMain, "Pin Matched", kLayer.Projection)
end

Controls['btnExit'].EventHandler = function()
  setPage(pageStart, "Exit", layerDefault)
end

Controls['ledTouchActivity'].EventHandler = function()
  resetTouchInactivityTimer()
end

timerInactivity.EventHandler = onTouchInactivityTimeout

----[ Always Run ]----

function funcInit()
  debugPrint("=== Initialization Started ===")
  setPage(pageStart, "Init")
  debugPrint("=== Initialization Complete ===")
end

funcInit()
