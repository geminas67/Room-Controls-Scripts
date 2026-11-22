--[[
  Input Selector - Q-SYS Control Script
  Author: Nikolas Smith
  Date: 2026-11-21
  Version: 1.1
  Firmware Req: Existing design requirements apply

  Interlocks inputs and Power Off; pulses power on for input selections.
]]

-------------------[ Configuration ]-------------------
projName = Controls["compProjector"].String
uciName = "uciController"
timePowerPulse = 1
inputNames = {
  "Barco Out 1",
  "Barco Out 2",
  "Podium Laptop",
  "Wallplate Laptop",
}
-------------------[ Constant Tables ]-------------------
compProj = Component.New(projName)
compUCI = Component.New(uciName)
btnInput = Controls['btnInput']
-------------------[ Constants ]-------------------

stateDebug = true
stateProjPower = false
timerPowerPulse = Timer.New()
-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(message)
  if stateDebug then print(message) end
end

-------------------[ Input Selection / Power ]-------------------

function powerReset()
  timerPowerPulse:Stop()
  Controls['btnPowerOn'].Boolean = false
end

function selectInput(selected)
  for i, ctl in ipairs(btnInput) do
    ctl.Boolean = (i == selected)
  end
  Controls['btnPowerOff'].Boolean = (selected == 0)

  if selected == 0 then
    powerReset()
    debugMsg("Power Off selected; inputs cleared.")
    return
  end

  local label = inputNames[selected] or string.format("%02d", selected)
  debugMsg(string.format("Input [%s] selected.", label))

  -- Do not send power On if already On or a pulse is active.
  if compProj['Power'].Boolean or Controls['btnPowerOn'].Boolean then return end

  Controls['btnPowerOn'].Boolean = true
  timerPowerPulse:Start(timePowerPulse)
  debugMsg("Projector power On pulsed.")
end

-------------------[ Event Handlers ]-------------------

timerPowerPulse.EventHandler = powerReset

for i, ctl in ipairs(btnInput) do
  local inputIndex = i
  ctl.EventHandler = function()
    selectInput(inputIndex)
  end
end

Controls['btnPowerOff'].EventHandler = function(ctl)
  if ctl.Boolean then selectInput(0) end
end

compUCI['btnExit'].EventHandler = function(ctl)
  selectInput(0)
end

-------------------[ Always Run ]-------------------

function funcInit()
  selectInput(0)
end

funcInit()
