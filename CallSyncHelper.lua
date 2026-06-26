--[[
    Call Sync Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-06-23
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the Call Sync in single room and divisible spaces.
]]

-------------------[ Control References ]-------------------
ledRoomA    = Component.New('ledBlinkingRmA')
ledRoomB    = Component.New('ledBlinkingRmB')
callSyncRmA = Component.New('callSyncCollabA')
callSyncRmB = Component.New('callSyncCollabB')
compDivSpace    = Component.New('compDivisibleSpaceControls')

function updateLedCallSync()
  if compDivSpace['btnRoomState 1'].Boolean then
    ledRoomA['enable'].Boolean = callSyncRmA['off.hook'].Boolean
    ledRoomB['enable'].Boolean = callSyncRmB['off.hook'].Boolean
  else
    inCall = callSyncRmA['off.hook'].Boolean or callSyncRmB['off.hook'].Boolean
    ledRoomA['enable'].Boolean = inCall
    ledRoomB['enable'].Boolean = inCall
  end
end

callSyncRmA['off.hook'].EventHandler = updateLedCallSync
callSyncRmB['off.hook'].EventHandler = updateLedCallSync
compDivSpace['btnRoomState 1'].EventHandler = updateLedCallSync

updateLedCallSync()