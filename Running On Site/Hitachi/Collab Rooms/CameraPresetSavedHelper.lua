--[[
    Camera Preset Saved Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the Camera Preset Controller(JSON)(Refactor).lua script.
]]

-------------------[ Control References ]-------------------
local camPresets = Component.New('camPresetsControlsCollab')
local uciCollabA = Component.New('uciControllerCollabA')
local uciCollabB = Component.New('uciControllerCollabB')
local divSpace   = Component.New('compDivisibleSpaceControls')

local numPresets = 6

local function anyLedSaved(comp, namePrefix)
  for i = 1, numPresets do
    if comp[namePrefix .. i].Boolean then return true end
  end
  return false
end

function pinLEDPresetSavedCollabA()
  uciCollabA['pinLEDPresetSaved'].Boolean = anyLedSaved(camPresets, 'ledPresetSaved1 ')
end

function pinLEDPresetSavedCollabB()
  local saved = anyLedSaved(camPresets, 'ledPresetSaved2 ')
  uciCollabB['pinLEDPresetSaved'].Boolean = false
  if not divSpace['btnRoomState 1'].Boolean then
    uciCollabA['pinLEDPresetSaved'].Boolean = saved
    uciCollabB['pinLEDPresetSaved'].Boolean = saved
  else
    uciCollabB['pinLEDPresetSaved'].Boolean = saved
  end
end

for i = 1, numPresets do
  camPresets['ledPresetSaved1 ' .. i].EventHandler = function() pinLEDPresetSavedCollabA() end
  camPresets['ledPresetSaved2 ' .. i].EventHandler = function() pinLEDPresetSavedCollabB() end
end
