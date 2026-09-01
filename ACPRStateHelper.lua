--[[
    ACPR State Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.1 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - Enables/disables camera preset and USB bridge controls based on ACPR TrackingBypass.
    - IsDisabled works on script/Text Controller pins (camPresetsControls, uciController).
    - Native USB Video Bridge pins do not support IsDisabled; wire UCI PTZ through uciController
      script pins (or Controls on this script) for gray-out behavior.
    - Syncs uciController ledACPRBypassActive to drive the J03-ACPRActive UCI overlay.
]]

-------------------[ Control References ]-------------------
compACPR = Component.New('compACPR')
compCamPreset = Component.New('camPresetsControls')
usbBridge01 = Component.New('usbBridgeCTL01')
usbBridge02 = Component.New('usbBridgeIOB01')

local usbBridgeControlNames = {
  "pan.left",
  "pan.right",
  "tilt.up",
  "tilt.down",
  "zoom.in",
  "zoom.out",
  "toggle.privacy",
  "preset.home.load",
}

local trackingBypassControls = {}
local controlSet = {}

local function addControl(ctl)
  if ctl and not controlSet[ctl] then
    controlSet[ctl] = true
    table.insert(trackingBypassControls, ctl)
  end
end

local function addNamedControls(comp, names)
  if not comp then return end
  for _, name in ipairs(names) do
    addControl(comp[name])
  end
end

local i = 1
while compCamPreset["btnCamPreset " .. i] do
  addControl(compCamPreset["btnCamPreset " .. i])
  i = i + 1
end

addNamedControls(uciController, usbBridgeControlNames)

for _, name in ipairs(usbBridgeControlNames) do
  if Controls[name] then
    addControl(Controls[name])
  end
end

addNamedControls(usbBridge01, usbBridgeControlNames)
addNamedControls(usbBridge02, usbBridgeControlNames)

function updateTrackingBypassControls()
  local bypass = compACPR["TrackingBypass"].Boolean
  local disabled = not bypass

  for _, ctl in ipairs(trackingBypassControls) do
    if ctl.IsDisabled ~= disabled then
      ctl.IsDisabled = disabled
    end
  end
end

compACPR["TrackingBypass"].EventHandler = updateTrackingBypassControls

updateTrackingBypassControls()

print("ACPRStateHelper: " .. #trackingBypassControls .. " controls bound to TrackingBypass")
