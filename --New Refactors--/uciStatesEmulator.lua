--[[
  UCI States Emulator
  Author: Nikolas Smith, Q-SYS
  Version: 1.4 | Date: 2026-10-30
  Emulates the UCI states for the UCI Controller.
  lblToggle[i].String = uciController control name (Script Access required).
  Controls.toggle[i].Boolean is authoritative; UCI controls follow (init/label change included).
  Schematic links on toggle[] bypass this script.
]]

-------------------[ Configuration ]-------------------
uciController = Component.New("uciController")

-------------------[ Constant Tables ]-------------------
boundUci = {}  -- [i] = UCI control currently reconciled for index i

-------------------[ Constants ]-------------------
toggleCount = #Controls.toggle

-------------------[ Functions ]-------------------
function uciControlForIndex(i)
  local name = Controls.lblToggle[i].String
  if name == "" then return nil, name end
  return uciController[name], name
end

function syncToggleToUci(i, log)
  local ctl, name = uciControlForIndex(i)
  if not ctl then return end
  local on = Controls.toggle[i].Boolean
  if ctl.Boolean ~= on then ctl.Boolean = on end
  if log then print(string.format("-- %s -- is %s.", name, on and "On" or "Off")) end
end

function bindUciReconcile(i)
  if boundUci[i] then boundUci[i].EventHandler = nil end
  boundUci[i] = uciControlForIndex(i)
  if boundUci[i] then
    boundUci[i].EventHandler = function() syncToggleToUci(i) end
  end
  syncToggleToUci(i)
end

-------------------[ Event Handlers ]-------------------
for i = 1, toggleCount do
  Controls.toggle[i].EventHandler = function()
    print("--------------------------------")
    print(string.format("Toggle%02d changed.", i))
    syncToggleToUci(i, true)
  end
  Controls.lblToggle[i].EventHandler = function() bindUciReconcile(i) end
end

-------------------[ Always Run ]-------------------
function funcInit()
  for i = 1, toggleCount do bindUciReconcile(i) end
end

funcInit()
