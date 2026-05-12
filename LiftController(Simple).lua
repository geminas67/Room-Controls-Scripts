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

function setFeedback(txt)
  print(txt)
  Controls.txtFeedback.String = txt
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

function setMovement(relayUp, relayDn, msg)
  Controls.pinRelayUp.Boolean = relayUp
  Controls.pinRelayDn.Boolean = relayDn
  Timer.CallAfter(clearPulseState, Controls.knbLatchTime.Value)
  setFeedback(msg)
  setDisabled(true)
end

function liftPosition(liftUp, liftDn, pos)
  Controls.ledPosition[1].Boolean = liftUp
  Controls.ledPosition[2].Boolean = liftDn
  setFeedback(pos)
end

-- Initialization --
resetControls()

Controls.btnMoveUp.EventHandler = function(ctl)
  if ctl.Boolean then
    setMovement(true, false, "Lift is rising. Controls will re-enable when movement stops.")
    timerMovementSet()
  end
end

Controls.btnMoveStop.EventHandler = function(ctl)
  if ctl.Boolean then
    timerMovementCancel()
    setMovement(true, true, "Lift is stopped")
    setDisabled(false)
  end
end

Controls.btnMoveDn.EventHandler = function(ctl)
  if ctl.Boolean then
    setMovement(false, true, "Lift is lowering. Controls will re-enable when movement stops.")
    timerMovementSet()
  end
end

Controls.ledPosition[1].EventHandler = function(ctl)
  if ctl.Boolean then
    liftPosition(true, false, "Lift is up")
  end
end

Controls.ledPosition[2].EventHandler = function(ctl)
  if ctl.Boolean then
    liftPosition(false, true, "Lift is down")
  end
end
