--[[
  Projector Lift Controller
  Version: 1.1
  Pulsed lift control with timed movement lockout.
]]--

-------------------[ Configuration ]-------------------

projName = "devProjector2000"

-------------------[ Constants ]-------------------

timerMovement, timerPulse = Timer.New(), Timer.New()

-------------------[ Functions ]-------------------

function setDisabled(disabled)
  Controls['btnMoveUp'].IsDisabled = disabled
  Controls['btnMoveDn'].IsDisabled = disabled
end

function setFeedback(txt)
  print(txt)
  Controls['txtFeedback'].String = txt
end

function clearPulseState()
  Controls['btnMoveUp'].Boolean = false
  Controls['btnMoveStop'].Boolean = false
  Controls['btnMoveDn'].Boolean = false
  Controls['pinRelayUp'].Boolean = false
  Controls['pinRelayDn'].Boolean = false
end

function setMovement(relayUp, relayDn, msg)
  timerPulse:Stop()
  clearPulseState()

  Controls['pinRelayUp'].Boolean = relayUp
  Controls['pinRelayDn'].Boolean = relayDn
  timerPulse:Start(Controls['knbLatchTime'].Value)

  setDisabled(true)
  setFeedback(msg)
end

function movementLocked()
  return timerMovement:IsRunning() or timerPulse:IsRunning()
end

-------------------[ Event Handlers ]-------------------

timerPulse.EventHandler = function()
  timerPulse:Stop()
  clearPulseState()
  setDisabled(timerMovement:IsRunning())
end

timerMovement.EventHandler = function()
  timerMovement:Stop()
  setDisabled(timerPulse:IsRunning())
  setFeedback("Lift is rising. Controls will re-enable when movement stops.")
end

Controls['btnMoveUp'].EventHandler = function(ctl)
  if not ctl.Boolean then return end
  ctl.Boolean = false
  if movementLocked() then return end
  if not devProj["ledPowerStatus 1"].Boolean then
    setFeedback("Cannot raise lift while projector is on.")
    return
  end
  timerMovement:Start(Controls['knbMovingTime'].Value)
  setMovement(true, false, "Lift is rising.")
end

Controls['btnMoveStop'].EventHandler = function(ctl)
  if not ctl.Boolean then return end
  timerMovement:Stop()
  setMovement(true, true, "Lift is stopped.")
end

Controls['btnMoveDn'].EventHandler = function(ctl)
  if not ctl.Boolean then return end
  ctl.Boolean = false
  if movementLocked() then return end
  timerMovement:Start(Controls['knbMovingTime'].Value)
  setMovement(false, true, "Lift is lowering.")
end

Controls.ledPosition[1].EventHandler = function(ctl)
  if ctl.Boolean then
    setFeedback("Lift is up.")
  end
end

Controls.ledPosition[2].EventHandler = function(ctl)
  if ctl.Boolean then
    setFeedback("Lift is down.")
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  devProj = Component.New(projName)
  timerMovement:Stop()
  timerPulse:Stop()
  clearPulseState()
  setDisabled(false)
  Controls['btnMoveStop'].IsDisabled = false
  Controls['txtFeedback'].String = "Lift Control"
end

funcInit()
