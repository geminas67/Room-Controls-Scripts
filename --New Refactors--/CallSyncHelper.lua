--[[
    Call Sync Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-10-04
    Firmware Req: 10.0.0+
    Notes:
    - This script is used to update the Blinking LED in each room when the Call Sync "off.hook" is active.
]]

-------------------[ Control References ]-------------------
ledRoomA    = Component.New('ledBlinkingRmA')
ledRoomB    = Component.New('ledBlinkingRmB')
callSyncRmA = Component.New('callSyncRmA')
callSyncRmB = Component.New('callSyncRmB')
compDivSpace = Component.New('compDivisibleSpaceControls')

local function isDivided()
  return compDivSpace['btnRoomMode 1'].Boolean
end

function updateBlinkingLED()
  if isDivided() then
    ledRoomA['enable'].Boolean = callSyncRmA['off.hook'].Boolean
    ledRoomB['enable'].Boolean = callSyncRmB['off.hook'].Boolean
  else
    local inCall = callSyncRmA['off.hook'].Boolean or callSyncRmB['off.hook'].Boolean
    ledRoomA['enable'].Boolean = inCall
    ledRoomB['enable'].Boolean = inCall
  end
end

callSyncRmA['off.hook'].EventHandler = updateBlinkingLED
callSyncRmB['off.hook'].EventHandler = updateBlinkingLED
compDivSpace['btnRoomMode 1'].EventHandler = updateBlinkingLED

updateBlinkingLED()