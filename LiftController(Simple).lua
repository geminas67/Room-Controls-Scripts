---Named Components---
compLift = Component.New("compProjector")

timerMovementEnd = nil

compLift["ledPower"].EventHandler = function(ctl)
  if not ctl.Boolean then
    print("Projector is off. Lift can now move up.")
  end
end

function setDisabled(boolean)
  Controls.btnMoveUp.IsDisabled = boolean
  Controls.btnMoveDn.IsDisabled = boolean
end

function setFeedback(text)
  print(text)
  Controls.txtFeedback.String = text
end

function timerMovementCancel()
  if timerMovementEnd then
    timerMovementEnd:Cancel()
    timerMovementEnd = nil
  end
end

function timerMovementSet()
  timerMovementCancel()
  timerMovementEnd = Timer.CallAfter(function()
    setDisabled(false)
    setFeedback("")
    timerMovementEnd = nil
  end, Controls.knbMovingTime.Value)
end

function clearPulseState()
  Controls.btnMoveUp.Boolean = false
  Controls.btnMoveStop.Boolean = false
  Controls.btnMoveDn.Boolean = false
  Controls.pinRelayUp.Boolean = false
  Controls.pinRelayDn.Boolean = false
end

function resetControls()
  timerMovementCancel()
  clearPulseState()
  setDisabled(false)
end

function trigger(relayUp, relayDn, message)
  Controls.pinRelayUp.Boolean = relayUp
  Controls.pinRelayDn.Boolean = relayDn
  Timer.CallAfter(clearPulseState, Controls.knbLatchTime.Value)
  setFeedback(message)
  setDisabled(true)
end

-- Initialization --
resetControls()

Controls.btnMoveUp.EventHandler = function(ctl)
  if ctl.Boolean then
    trigger(true, false, "Screen is going up. Controls will reenable once the screen has stopped moving.")
    timerMovementSet()
  end
end

Controls.btnMoveStop.EventHandler = function(ctl)
  if ctl.Boolean then
    timerMovementCancel()
    trigger(true, true, "Screen is stopped")
    setDisabled(false)
  end
end

Controls.btnMoveDn.EventHandler = function(ctl)
  if ctl.Boolean then
    trigger(false, true, "Screen is going down. Controls will reenable once the screen has stopped moving.")
    timerMovementSet()
  end
end
