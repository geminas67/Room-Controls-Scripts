--[[
  UCI States Emulator
  Author: Nikolas Smith, Q-SYS
  Version: 1.1 | Date: 2026-10-15
  Firmware Req: 10.4
  Emulates the UCI states for the UCI Controller.
  lblToggle[i].String = uciController control name; toggle[i] writes its .Boolean.
  Schematic links on toggle[] bypass this script. Clear handlers: EventHandler = nil before assign.
]]

-------------------[ Configuration ]-------------------
uciController = Component.New("uciController")

-------------------[ Functions ]-------------------
function bind(ctrl, fn)
  if not ctrl or not fn then return end
  ctrl.EventHandler = nil
  ctrl.EventHandler = fn
end

function uciStateToggle(i)
  local name = Controls.lblToggle[i] and Controls.lblToggle[i].String or ""
  if name == "" then return end
  local ctl = uciController[name]
  if not ctl then return end
  local on = Controls.toggle[i].Boolean
  if ctl.Boolean ~= on then ctl.Boolean = on end
  print(string.format("-- %s -- is %s.", name, on and "On" or "Off"))
end

function bindToggle(i)
  bind(Controls.toggle[i], function()
    print("--------------------------------")
    print(string.format("Btn%02d pressed.", i))
    uciStateToggle(i)
  end)
end

-------------------[ Event Handlers ]-------------------
for i = 1, #Controls.toggle do bindToggle(i) end
for i = 1, #Controls.lblToggle do
  bind(Controls.lblToggle[i], function() bindToggle(i) end)
end
