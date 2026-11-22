--[[
  Projection screen control - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 1.2 | Date: 2026-11-17

  Independent relay pulse, command feedback, and estimated travel timers.
  Position LEDs indicate estimated endpoints, not confirmed position.
]]--

-------------------[ Constants ]-------------------

timerPulse, timerFeedback, timerMovement = Timer.New(), Timer.New(), Timer.New()
movementUp = false

-------------------[ Functions ]-------------------

function setDisabled(disabled)
  Controls['btnMoveUp'].IsDisabled = disabled
  Controls['btnMoveDn'].IsDisabled = disabled
end

function clearFeedback()
  timerFeedback:Stop()
  Controls['txtFeedback'].String = "Screen"
end

function showFeedback(message)
  timerFeedback:Stop()
  print(message)
  Controls['txtFeedback'].String = message
end

function setFeedback(message)
  showFeedback(message)
  timerFeedback:Start(3)
end

function screenPosition(screenUp, screenDn)
  Controls['ledPosition'][1].Boolean = screenUp
  Controls['ledPosition'][2].Boolean = screenDn
end

function clearPulseState()
  timerPulse:Stop()

  Controls['pinRelayUp'].Boolean = false
  Controls['pinRelayDn'].Boolean = false

  Controls['btnMoveUp'].Boolean = false
  Controls['btnMoveDn'].Boolean = false
  Controls['btnMoveStop'].Boolean = false

  setDisabled(timerMovement:IsRunning())
end

function movementComplete()
    timerMovement:Stop()
    screenPosition(movementUp, not movementUp)
    setDisabled(timerPulse:IsRunning())
    setFeedback(movementUp and "Screen is up" or "Screen is down")
end
  
function setMovement(relayUp, relayDn, message)
  timerPulse:Stop()
  timerMovement:Stop()

  -- Neither endpoint is assumed once a new command is sent.
  screenPosition(false, false)

  Controls['pinRelayUp'].Boolean = relayUp
  Controls['pinRelayDn'].Boolean = relayDn

  Controls['btnMoveUp'].Boolean = relayUp and not relayDn
  Controls['btnMoveDn'].Boolean = relayDn and not relayUp
  Controls['btnMoveStop'].Boolean = relayUp and relayDn

  setDisabled(true)

  if relayUp ~= relayDn then
    movementUp = relayUp
    showFeedback(message)
    timerMovement:Start(Controls['knbTravelTime'].Value)
  else
    setFeedback(message)
  end
  timerPulse:Start(Controls['knbLatchTime'].Value)
end

-------------------[ Event Handlers ]-------------------

timerPulse.EventHandler = clearPulseState
timerFeedback.EventHandler = clearFeedback
timerMovement.EventHandler = movementComplete

Controls['btnMoveUp'].EventHandler = function(ctl)
  if ctl.Boolean then
    setMovement(true, false, "Screen is rising")
  end
end

Controls['btnMoveStop'].EventHandler = function(ctl)
  if ctl.Boolean then
    setMovement(true, true, "Screen is stopped")
  else
    ctl.Boolean = timerPulse:IsRunning()
  end
end

Controls['btnMoveDn'].EventHandler = function(ctl)
  if ctl.Boolean then
    setMovement(false, true, "Screen is lowering")
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  timerMovement:Stop()
  clearPulseState()
  clearFeedback()
  screenPosition(false, false)
  Controls['btnMoveStop'].IsDisabled = false
end

funcInit()
