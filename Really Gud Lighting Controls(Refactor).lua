--[[
  Really Gud Lighting Controls - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-06-24
  Version: 2.0
  Firmware Req: 10.1.0

  Lighting preset buttons, level fader, and TCP feedback from a lighting controller.

]]--

-------------------[ Configuration ]-------------------

lightingLevels = {
  99, -- 100%
  66, -- 66%
  33, -- 33%
  0,  -- 0%
}

levelToButton = {}
for i, level in ipairs(lightingLevels) do
  levelToButton[level] = i
end

-------------------[ Constants ]-------------------

stateDebug = true
devLights = TcpSocket.New()
pollLevel = Timer.New()

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print(str)
end

-------------------[ Interlock ]-------------------

function interlockPresets(index)
  for i, ctl in ipairs(Controls.btnLightingPreset) do
    ctl.Boolean = (i == index)
  end
end

-------------------[ Commands ]-------------------

function sendLevelCommand(level)
  cmd = string.format("SETLVL:%02d\r", level)
  debugMsg("sendLevelCommand: " .. cmd)
  devLights:Write(cmd)
end

function applyPreset(index)
  interlockPresets(index)
  sendLevelCommand(lightingLevels[index])
end

-------------------[ Connection ]-------------------

function stopPolling()
  pollLevel:Stop()
end

function establishConnection()
  devLights:Disconnect()
  stopPolling()
  if Controls.txtIPAddress.String == "" then
    debugMsg("establishConnection: IP address is blank. Please enter good IP info.")
    return
  end
  devLights:Connect(Controls.txtIPAddress.String, Controls.knbPortNumber.Value)
  debugMsg("establishConnection attempted with: IP Address:" .. Controls.txtIPAddress.String .. " Port:" .. Controls.knbPortNumber.Value)
end

-------------------[ Feedback ]-------------------

function parseLevelResponse(line)
  debugMsg("parseLevelResponse Rx: " .. line)
  if not string.find(line, "LVL@") then
    debugMsg("parseLevelResponse: These are not the droids you are looking for.")
    return
  end
  level = tonumber(string.sub(line, -2, -1))
  debugMsg("parseLevelResponse level: " .. tostring(level) .. " " .. type(level))
  Controls.fdrLevel.Value = level
  interlockPresets(levelToButton[level])
end

function drainSocketLines()
  line = devLights:ReadLine(TcpSocket.EOL.Custom, "\r")
  while line ~= nil do
    parseLevelResponse(line)
    line = devLights:ReadLine(TcpSocket.EOL.Custom, "\r")
  end
end

-------------------[ Event Handlers ]-------------------

for i, ctl in ipairs(Controls.btnLightingPreset) do
  ctl.EventHandler = function()
    applyPreset(i)
  end
end

Controls.fdrLevel.EventHandler = function(ctl)
  sendLevelCommand(ctl.Value)
end

pollLevel.EventHandler = function()
  devLights:Write("GETLVL\r")
  debugMsg("pollLevel: pingy ping ping")
end

Controls.txtIPAddress.EventHandler = establishConnection
Controls.knbPortNumber.EventHandler = establishConnection

socketStopEvents = {
  [TcpSocket.Events.Closed] = "Closed",
  [TcpSocket.Events.Error] = "Error",
  [TcpSocket.Events.Timeout] = "Timeout",
}

devLights.EventHandler = function(sock, evt, err)
  if evt == TcpSocket.Events.Connected then
    debugMsg("devLights is Connected")
    pollLevel:Start(2)
  elseif evt == TcpSocket.Events.Reconnect then
    debugMsg("devLights is Reconnect")
  elseif evt == TcpSocket.Events.Data then
    drainSocketLines()
  elseif socketStopEvents[evt] then
    debugMsg("devLights is " .. socketStopEvents[evt])
    stopPolling()
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  Controls.fdrLevel.RampTime = 0.5
  establishConnection()
end

funcInit()
