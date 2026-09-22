--[[
    Camera Preset Saved Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the Camera Preset Controller(JSON)(Refactor).lua script.
]]

-------------------[ Control References ]-------------------
camPresets = Component.New('camPresetsControls')
uciRoomA = Component.New('uciControllerRoomA')
uciRoomB = Component.New('uciControllerRoomB')
divSpace   = Component.New('compDivisibleSpaceControls')

numPresets = 6

function anyLedSaved(comp, namePrefix)
  for i = 1, numPresets do
    if comp[namePrefix .. i].Boolean then return true end
  end
  return false
end

function pinLEDPresetSavedRoomA()
  uciRoomA['pinLEDPresetSaved'].Boolean = anyLedSaved(camPresets, 'ledPresetSaved1 ')
end

function pinLEDPresetSavedRoomB()
  local saved = anyLedSaved(camPresets, 'ledPresetSaved2 ')
  uciRoomB['pinLEDPresetSaved'].Boolean = false
  if not divSpace['btnRoomState 1'].Boolean then
    uciRoomA['pinLEDPresetSaved'].Boolean = saved
    uciRoomB['pinLEDPresetSaved'].Boolean = saved
  else
    uciRoomB['pinLEDPresetSaved'].Boolean = saved
  end
end

for i = 1, numPresets do
  camPresets['ledPresetSaved1 ' .. i].EventHandler = function() pinLEDPresetSavedRoomA() end
  camPresets['ledPresetSaved2 ' .. i].EventHandler = function() pinLEDPresetSavedRoomB() end
end
