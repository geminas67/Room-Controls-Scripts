--[[
  Interlock Emulator
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2026-10-01
  Firmware Req: 10.4
  Emulates the interlock input signals for the matrix device
]]

-------------------[ Configuration ]-------------------
devMatrix = Component.New("devMatrixDXP")

btnIndexToInputSignal = {
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
  [5] = 3,
  [6] = 4,
  [7] = nil
}

function interlockInput(btnIndex)
  local selectedInput = btnIndexToInputSignal[btnIndex]

  for i = 1, #Controls.btnSignal do
    Controls.btnSignal[i].Boolean = (i == btnIndex)
  end

  for i = 1, 4 do
    local isActive = (i == selectedInput)
    devMatrix["input.signal " .. i].Boolean = isActive
  
    if isActive then
      print(string.format("Matrix input LED%02d was activated.", i))
    end
  end
  
end

for i = 1, #Controls.btnSignal do
  Controls.btnSignal[i].EventHandler = function()
    print('--------------------------------')
    print(string.format('Btn%02d was pressed.', i))
    interlockInput(i)
  end
end
