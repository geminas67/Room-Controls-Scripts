--[[
    Camera Preset Saved Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the Camera Preset Controller(JSON)(Refactor).lua script.
]]

-------------------[ Control References ]-------------------
local camPresets = Component.New('camPresetsControls')
local uciA = Component.New('uciControllerRmA')
local uciB = Component.New('uciControllerRmB')
local divSpace = Component.New('compDivisibleSpaceControls')

local numPresets = 6

local function anyLedSaved(comp, namePrefix)
  for i = 1, numPresets do
    if comp[namePrefix .. i].Boolean then return true end
  end
  return false
end

function ledPresetSavedRmA()
  uciA['ledPresetSaved'].Boolean = anyLedSaved(camPresets, 'ledPresetSaved1 ')
end

function ledPresetSavedRmB()
  local saved = anyLedSaved(camPresets, 'ledPresetSaved2 ')
  uciB['ledPresetSaved'].Boolean = false
  if not divSpace['btnRoomState 1'].Boolean then
    uciA['ledPresetSaved'].Boolean = saved
    uciB['ledPresetSaved'].Boolean = saved
  else
    uciB['ledPresetSaved'].Boolean = saved
  end
end

for i = 1, numPresets do
  camPresets['ledPresetSaved1 ' .. i].EventHandler = function() ledPresetSavedRmA() end
  camPresets['ledPresetSaved2 ' .. i].EventHandler = function() ledPresetSavedRmB() end
end
