--[[
  Interlocking Emulator — Q-SYS script for training room interlocking
  Author: Nikolas Smith, Q-SYS
  Date: 2026-04-09
  Version: 1.0
  Firmware Req: 10.2.0
  Description: Emulates interlocking behavior for training room buttons and matrix inputs.
--]]

-------------------[ Component References ]-------------------

devMatrixDXP = Component.New('devMatrixDXP')

-------------------[ Controls ]-------------------

local numBtns = 7
local numMatrixInputs = 4

-- Which devMatrixDXP input (1–4) follows each button; 7 = buttons only, no matrix
local btnIndexToMatrixInput = {
    [1] = 1, [2] = 2, [3] = 3, [4] = 4,
    [5] = 3, [6] = 4, [7] = nil,
}

function funcInterlock(ctlActive)
    for i = 1, numBtns do
        Controls.btnSignal[i].Boolean = false
    end
    for mi = 1, numMatrixInputs do
        devMatrixDXP['input.signal ' .. mi].Boolean = false
    end
    Controls.btnSignal[ctlActive].Boolean = true
    local matrixInput = btnIndexToMatrixInput[ctlActive]
    if matrixInput then
        devMatrixDXP['input.signal ' .. matrixInput].Boolean = true
        print(string.format('Matrix input LED%02d was activated.', matrixInput))
    end
end

for idx = 1, numBtns do
    Controls.btnSignal[idx].EventHandler = function()
        print('                        ')
        print(string.format('Btn%02d was pressed.', idx))
        funcInterlock(idx)
    end
end
