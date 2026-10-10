--[[
  UCI States Emulator
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2026-10-01
  Firmware Req: 10.4
  Emulates the UCI states for the UCI Controller.
]]

-------------------[ Configuration ]-------------------
uciController = Component.New("uciControllerRmA")

btnIndexToUCIControl = {
  [1] = "ledACPRBypassCombined",
  [2] = "ledACPRBypassSeparated",
  [3] = "ledHDMIActiveLaptopA",
  [4] = "ledHDMIActiveLaptopB",
  [5] = "ledHDMIActivePCA",
  [6] = "ledHDMIActivePCB",
  [7] = "ledHDMILaptopA",
  [8] = "ledHDMILaptopB",
  [9] = "ledHDMIPCA",
  [10] = "ledHDMIPCB",
  [11] = "ledOffHook",
  [12] = "ledOffHookLaptopA",
  [13] = "ledOffHookLaptopB",
  [14] = "ledOffHookPCA",
  [15] = "ledOffHookPCB",
  [16] = "ledPresetSaved",
  [17] = "ledUSBLaptopA",
  [18] = "ledUSBLaptopB",
  [19] = "ledUSBPCA",
  [20] = "ledUSBPCB",
  [21] = "ledTouchActivity",
}

for i = 1, #Controls.lblToggle do
  controlName = btnIndexToUCIControl[i]
  if controlName then
    Controls.lblToggle[i].String = controlName
  end
end

function uciStateToggle(btnIndex)
  local controlName = btnIndexToUCIControl[btnIndex]
  if not controlName then
    return
  end

  local isOn = Controls.toggle[btnIndex].Boolean
  uciController[controlName].Boolean = isOn

  if isOn then
    print(string.format("-- %s -- is On.", controlName))
  else
    print(string.format("-- %s -- is Off.", controlName))
  end
end

for i = 1, #Controls.toggle do
  Controls.toggle[i].EventHandler = function()
    print("--------------------------------")
    print(string.format("Btn%02d pressed.", i))
    uciStateToggle(i)
  end
end
