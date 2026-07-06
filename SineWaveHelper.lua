--[[
    Sine Generator Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-31
    Firmware Req: 10.1.0
    Notes:
    - This script is used to set the frequency of the sine wave generator.
]]

-------------------[ Control References ]-------------------
local sineGen = Component.New('sineGenerator')

local valuesSines = {
  '400',
  '800',
  '1000',
  '2000',
  '4000',
  '8000',
}

local function interlockSineButtons(index)
  for i,ctl in ipairs(Controls.btnPreset) do
    ctl.Boolean = (i == index)
  end
end

local function setSine(index)
  sineGen['frequency'].Value = tonumber(valuesSines[index])
  interlockSineButtons(index)
end

for i = 1, #valuesSines do
  Controls.btnPreset[i].Legend = valuesSines[i] .. 'Hz'
  Controls.btnPreset[i].EventHandler = function() setSine(i) end
end
