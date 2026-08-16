--[[
    Camera Preset Saved Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the Camera Preset Controller(JSON)(Refactor).lua script.
]]


-------------------[ Control References ]-------------------
local camControls = Component.New('camControls')
local uciController = Component.New('uciControllerAuditorium')

local numPresets = 4

local function anyLedSaved(comp, namePrefix)
  for i = 1, numPresets do
    if comp[namePrefix .. i].Boolean then return true end
  end
  return false
end

function pinLEDPresetSaved()
  uciController['pinLEDPresetSaved'].Boolean = anyLedSaved(camControls, 'ledPresetSave')
end


for i = 1, numPresets do
  camControls['ledPresetSave' .. i].EventHandler = function() pinLEDPresetSaved() end
end
