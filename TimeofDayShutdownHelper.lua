---@diagnostic disable: inject-field
--[[
    Time of Day Shutdown (System Reset)
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-02-01
    Firmware Req: 10.0.0
    Description: Responds to Time of Day Active change and triggers Power Off commands.
]]

-------------------[ Configuration ]-------------------

enableTime = {
  hour = 7,
  min = 0,
}

roomConfig = {
  { roomControlName = "roomControlsCollabA", componentName = "compRoomControlsCollabA", roomName = "Collab A" },
  { roomControlName = "roomControlsCollabB", componentName = "compRoomControlsCollabB", roomName = "Collab B" },
}

-------------------[ Constant Tables ]-------------------

component = {
  todShutdown = Component.New("todShutdown"),
}

for _, config in ipairs(roomConfig) do
  component[config.componentName] = Component.New(config.componentName)
end

-------------------[ Constants ]-------------------

stateDebug = false
timerEnableCheck = Timer.New()

-------------------[ Functions ]-------------------

function debugMsg(str)
  if stateDebug then
    print("[TimeOfDayShutdown] " .. str)
  end
end

function syncEnableToComponent(enabled)
  local enableCtrl = component.todShutdown and component.todShutdown.enable
  if enableCtrl then
    enableCtrl.Boolean = enabled
  end
end

-------------------[ Time of Day Shutdown ]-------------------

function handleTimeOfDayShutdown()
  if not Controls.btnResetEnabled.Boolean then
    debugMsg("Enable is false, shutdown skipped")
    return
  end

  local activeCtrl = component.todShutdown.active
  if not activeCtrl or not activeCtrl.Boolean then
    debugMsg("Active is false, returning early")
    return
  end

  print("Time of Day Shutdown triggered - powering off all rooms")

  for _, config in ipairs(roomConfig) do
    local roomControl = component[config.componentName]
    if roomControl and roomControl.btnSystemOff then
      print("  Triggering power off for " .. config.roomName)
      local success, err = pcall(function()
        roomControl.btnSystemOff:Trigger()
      end)
      if not success then
        print("  ERROR: Failed to trigger power off for " .. config.roomName .. ": " .. tostring(err))
      end
    else
      print("  WARNING: Could not access btnSystemOff for " .. config.roomName)
    end
  end
end

function handleEnableChange()
  local enableCtrl = Controls.btnResetEnabled
  local timeStr = string.format("%02d:%02d", enableTime.hour, enableTime.min)

  if enableCtrl.Boolean then
    enableCtrl.Legend = "Enabled"
    print("Time of Day shutdown enabled")
  else
    enableCtrl.Legend = "Disabled\nEnabled at " .. timeStr
    print("Time of Day shutdown disabled - will re-enable at " .. timeStr)
  end

  syncEnableToComponent(enableCtrl.Boolean)
end

function checkAndEnableAtTimeConfig()
  local currentTime = os.date("*t")

  if currentTime.hour == enableTime.hour and currentTime.min == enableTime.min then
    local enableCtrl = Controls.btnResetEnabled
    if enableCtrl and not enableCtrl.Boolean then
      local timeStr = string.format("%02d:%02d", enableTime.hour, enableTime.min)
      print(timeStr .. " reached - enabling Time of Day shutdown")
      enableCtrl.Boolean = true
      syncEnableToComponent(true)
    end
  end
end

-------------------[ Event Handlers ]-------------------

component.todShutdown.active.EventHandler = handleTimeOfDayShutdown
Controls.btnResetEnabled.EventHandler = handleEnableChange

-------------------[ Always Run ]-------------------

function funcInit()
  if not component.todShutdown.active or not component.todShutdown.enable then
    print("ERROR: TimeOfDayShutdown - todShutdown active/enable controls missing")
    return
  end
  if not Controls.btnResetEnabled then
    print("ERROR: TimeOfDayShutdown - btnResetEnabled control missing")
    return
  end

  handleEnableChange()
  timerEnableCheck:Start(checkAndEnableAtTimeConfig, 60)
  print("TimeOfDayShutdown initialized successfully")
end

funcInit()
