-- Screen control: press → relay on → after hold time → reset (relay off, button off)

local function setDisabled(boolean)
  Controls.btnScreenUp.IsDisabled = boolean
  Controls.btnScreenDn.IsDisabled = boolean
end

local function setFeedback(text)
  print(text)
  Controls.txtFeedback.String = text
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
  Timer.CallAfter(reset, Controls.knbHoldTime.Value)
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
