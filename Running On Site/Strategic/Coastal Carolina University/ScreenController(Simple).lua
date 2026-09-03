-- Screen control: press → relay on → after hold time → reset (relay off, button off)

local function setDisabled(boolean)
  Controls.btnScreenUp.IsDisabled = boolean
  Controls.btnScreenDn.IsDisabled = boolean
  Controls.btnScreenStop.IsDisabled = boolean
end

local function setFeedback(msg)
  print(msg)
  Controls.txtFeedback.String = msg
end

local function reset()
  Controls.btnScreenUp.Boolean = false
  Controls.btnScreenStop.Boolean = false
  Controls.btnScreenDn.Boolean = false
  Controls.pinRelayUp.Boolean = false
  Controls.pinRelayDn.Boolean = false
  setFeedback("")
  setDisabled(false)
end

local function trigger(relayUp, relayDn, message)
  Controls.pinRelayUp.Boolean = relayUp
  Controls.pinRelayDn.Boolean = relayDn
  Timer.CallAfter(reset, Controls.knbPulseLatch.Value)
  setFeedback(message)
  setDisabled(true)
end

-- Init
reset()

Controls.btnScreenUp.EventHandler = function(ctl)
  if ctl.Boolean then trigger(true, false, "Screen Up") end
end

Controls.btnScreenStop.EventHandler = function(ctl)
  if ctl.Boolean then trigger(true, true, "Screen Stopped") end
end

Controls.btnScreenDn.EventHandler = function(ctl)
  if ctl.Boolean then trigger(false, true, "Screen Down") end
end
