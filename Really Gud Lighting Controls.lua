--for each btnPreset
--for each event
--1.Interlock
--2.Prepeare the commmand string
--3. Send the command strings

arrLightingLevels = { --Lighting Preset levels as intergers
  99, --100%
  66, --66%
  33, --33%
  0,  --0%
}
tblLevelstoButtons = {} --tblLevelstoButtons[lvlNum]

for btnNum,lvlNum in pairs(arrLightingLevels) do
  tblLevelstoButtons[lvlNum] = btnNum            
end

function funcInterlock(argIndex) --set Booolean of button Index that was pressed, if not Index set button Boolean = false
  for i,ctl in ipairs(Controls.btnLightingPreset) do
  ctl.Boolean = (i == argIndex)
  end --for
end

function funcMakeLevelCommand(argNumber)
  local temp = string.format("SETLVL:%02d\r", argNumber)
  return temp
end

function funcSendLevelCommand(argNumber)
  tempLightingLevelsString = funcMakeLevelCommand(argNumber)
  print("funcSendLevelCommand is: ", tempLightingLevelsString)
  devLights:Write(tempLightingLevelsString)
end

for i,ctl in ipairs(Controls.btnLightingPreset) do --for each button preset, print its index
  ctl.EventHandler = function()
    funcInterlock(i)
    --tempLightingLevelsString = "SETLVL:"..arrLightingLevels[i].."\r"
    --tempLightingLevelsString = string.format("SETLVL:%02d\r", arrLightingLevels[i])
    --tempLightingLevelsString = funcMakeLevelCommand(arrLightingLevels[i])
    --print("tempLightingLevelsString is: ", tempLightingLevelsString)
    --devLights:Write(tempLightingLevelsString)
    funcSendLevelCommand(arrLightingLevels[i])
    --Controls.fdrLevel.Value = arrLightingLevels[i]--FAKE FEEDBACK REPLACE ME!

  end
end --loop

Controls.fdrLevel.EventHandler = function(ctl)
  funcSendLevelCommand(ctl.Value)
  --funcInterlock(nil)--FAKE FEEDBACK REPLACE ME!
end

Controls.fdrLevel.RampTime = 0.5 --make a nice sliding effect

pollLevel = Timer.New()

pollLevel.EventHandler = function ()
  devLights:Write("GETLVL\r")
  print("pollLevel: pingy ping ping")
end


devLights = TcpSocket.New() --creates the TCP socket
--devLights:Connect("127.0.0.1",5103)
function funcEstablishConnection()
  devLights:Disconnect()--hang up the connection
  pollLevel:Stop()
  if Controls.txtIPAddress.String ~= "" then
    devLights:Connect(Controls.txtIPAddress.String, Controls.knbPortNumber.Value)
    print("funcEstablishConnection attempted with: ", "IP Address:"..Controls.txtIPAddress.String, "Port:"..Controls.knbPortNumber.Value)
  else
    print("funcEstablishConnection: IP address is blank. Please enter good IP info.")
  end --if
end





funcEstablishConnection()--at Startup
Controls.txtIPAddress.EventHandler = funcEstablishConnection
Controls.knbPortNumber.EventHandler = funcEstablishConnection
          
    --we receive a string
    --sort it into "Important" and "Not important"
    --"extract" the  XXchar
    --conver XXchar into XXnum
    --upadte the fader with the real level (XXnum)
function funcLevelParser(argString)
  print("funcLevelParser Rx: ", argString)
  if string.find(argString,"LVL@") ~= nil then
    varActualLevel = tonumber(string.sub(argString,-2,-1))
    print("funcLevelParser varActualLevel: ",varActualLevel, type(varActualLevel))
    Controls.fdrLevel.Value = varActualLevel
    funcInterlock(tblLevelstoButtons[varActualLevel])
  else
    print("funcLevelParser: These are not the droids you are looking for.")
  end 
end

devLights.EventHandler = function( sock, evt, err )
  if evt == TcpSocket.Events.Connected then
    print("devLights is Connected")
    pollLevel:Start(2)
  elseif evt == TcpSocket.Events.Reconnect then
    print("devLights is Reconnect")
  elseif evt == TcpSocket.Events.Data then
    --print("devLights is Data")
    tempStringRemovedFromBuffer = devLights:ReadLine(TcpSocket.EOL.Custom, "\r")--destructively removes from the buffer, delimeter is removed 
    while tempStringRemovedFromBuffer ~= nil do
      funcLevelParser(tempStringRemovedFromBuffer)
      tempStringRemovedFromBuffer = devLights:ReadLine(TcpSocket.EOL.Custom, "\r")-- if there is more than one line of response
    end--loop
  elseif evt == TcpSocket.Events.Closed then
    print("devLights is Closed")
    pollLevel:Stop()                   
  elseif evt == TcpSocket.Events.Error then
    print("devLights is Error")
    pollLevel:Stop()
  elseif evt == TcpSocket.Events.Timeout then
    print("devLights is Timeout")
    pollLevel:Stop()
  end--if
end--tcp



