--[[
    Heyn Industries — Projector 2000 Controller
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-05-08
    Firmware Req: 10.3.0
    Notes:
    - TCP port 5101 (default); commands terminate with CR (0x0D).
    - POWER:1 on, POWER:0 off, POWER:? query — device replies ACK/NACK; status is 1–4.
    - Power states: 1=OFF, 2=WARMING, 3=ON, 4=COOLING (warm/cool may take 3–8 s).
]]

-------------------** Runtime Options **-------------------
modeOffline = false -- Set true to log commands without TCP
tcpPort = 5101
--- Interval (seconds) for POWER:? polling while projector is warming / cooling (3–8s per instruction).
amtPollTime = 1.5
--- Message terminator per instruction.
txtEOL = "\x0D"

sockTimeoutRead      = 0 -- Max wait for a read to complete before Timeout event (seconds)
sockTimeoutWrite     = 5 -- Max wait for a write to complete before Timeout event (seconds)
sockTimeoutReconnect = 5 -- Set the wait time before reconnecting (seconds)

-------------------** State **-------------------
currentPowerState = nil
tcpSocket = TcpSocket.New() -- Create new TcpSocket object
tcpSocket.ReadTimeout       = sockTimeoutRead
tcpSocket.WriteTimeout      = sockTimeoutWrite
tcpSocket.ReconnectTimeout  = sockTimeoutReconnect

pollTransitions = Timer.New()

-------------------** Helpers **-------------------
function debugMsg(msg)
    print("[Projector2000] " .. tostring(msg))
end

function setStatus(txt)
    Controls.txtStatus.String = tostring(txt or "")
    debugMsg(txt)
end

-- Interlock: ledPowerStatus[1 - 4] match power state (1=OFF … 4=COOLING)
function setPowerStatusLEDs(state)
    for i = 1, 4 do
        Controls.ledPowerStatus[i].Boolean = (i == state)
    end
end
function parsePowerState(line)
    if not line or line == "" then
        return nil
    end
    s = line:gsub("^%s+", ""):gsub("%s+$", "")
    if s:upper():find("NACK", 1, true) then
        return nil, "NACK"
    end
    d = s:match("POWER%s*:%s*([1-4])")
        or s:match("STATUS%s*:%s*([1-4])")
        or s:match("STATE%s*:%s*([1-4])")
        or s:match("[:=]%s*([1-4])")
        or s:match("^%s*([1-4])%s*$")
    if d then
        return tonumber(d)
    end
    return nil
end

function isTransitionState(state)
    return state == 2 or state == 4
end

-- Disable power commands while WARMING (2) / COOLING (4) — matches ledPowerStatus[2]/[4] feedback.
function btnDisabledState(state)
    disable = isTransitionState(state)
    Controls.btnPowerOn.IsDisabled = disable
    Controls.btnPowerOff.IsDisabled = disable
    Controls.btnPowerToggle.IsDisabled = disable
end

-- Hope Roth-style: one place drives toggle + on/off control FB (WARMING/ON ⇒ true).
function setPowerControlsFB(state)
    Controls.btnPowerToggle.Boolean = state
    Controls.btnPowerOn.Boolean = state
    Controls.btnPowerOff.Boolean = not state
end

function tcpSend(request, label)
    if modeOffline then
        debugMsg("[MOCK TX] " .. tostring(label) .. ": " .. request:gsub(txtEOL, "<CR>"))
        return true
    end
    if not tcpSocket.IsConnected then
        setStatus("Not connected — command not sent")
        debugMsg("tcpSend skipped (" .. tostring(label) .. "): socket not connected")
        return false
    end
    tcpSocket:Write(request)
    return true
end

function queryPower(reason)
    tcpSend("POWER:?" .. txtEOL, reason or "POWER:?")
end

function cmdPowerOn()
    if tcpSend("POWER:1" .. txtEOL, "POWER:1") then
        setPowerControlsFB(true)
    end
end

function cmdPowerOff()
    if tcpSend("POWER:0" .. txtEOL, "POWER:0") then
        setPowerControlsFB(false)
    end
end

function stopTransitionPoll()
    pollTransitions:Stop()
end

-- Reset UI/state when socket drops (Closed/Error/Timeout). Timeout does not raise Closed — Q-SYS docs.
function onSocketDropped(statusMsg, detailForLog)
    stopTransitionPoll()
    currentPowerState = nil
    setPowerStatusLEDs(nil)
    setPowerControlsFB(false)
    btnDisabledState(nil)
    setStatus(statusMsg)
    if detailForLog ~= nil and tostring(detailForLog) ~= "" then
        debugMsg(detailForLog)
    end
end

function applyPowerState(state, updateStatusLine)
    if not state or state < 1 or state > 4 then
        return
    end
    currentPowerState = state
    setPowerStatusLEDs(state)
    setPowerControlsFB(state == 2 or state == 3)
    btnDisabledState(state)
    labels = { "OFF", "WARMING", "ON", "COOLING" }
    if updateStatusLine then
        setStatus("Power: " .. labels[state] .. " (" .. tostring(state) .. ")")
    end
end

pollTransitions.EventHandler = function()
    pollTransitions:Stop()
    if not modeOffline and not tcpSocket.IsConnected then
        return
    end
    queryPower("Warm/cool poll")
    if currentPowerState and isTransitionState(currentPowerState) then
        pollTransitions:Start(amtPollTime)
    end
end

function startTransitionPollingIfNeeded(state)
    if state and isTransitionState(state) then
        pollTransitions:Start(amtPollTime)
    else
        stopTransitionPoll()
    end
end

function processIncomingLine(line)
    state, err = parsePowerState(line)
    if err == "NACK" then
        setStatus("Command rejected (NACK)")
        return
    end
    if state then
        applyPowerState(state, true)
        startTransitionPollingIfNeeded(state)
        return
    end
    if line ~= "" then
        debugMsg("RX: " .. line)
    end
end

function tcpConnect()
    stopTransitionPoll()
    if modeOffline then
        setStatus("modeOffline — no TCP")
        debugMsg("modeOffline: TCP skipped")
        return
    end
    tcpSocket:Disconnect()
    ip = Controls.txtIPAddress and Controls.txtIPAddress.String or ""
    if ip == "" then
        setStatus("Enter projector IP address")
        debugMsg("tcpConnect: IP blank")
        return
    end
    port = tcpPort
    if Controls.knbPortNumber and Controls.knbPortNumber.Value then
        v = Controls.knbPortNumber.Value
        if v and v > 0 then
            port = math.floor(v + 0.5)
        end
    end
    tcpSocket:Connect(ip, port)
    debugMsg("tcpConnect " .. ip .. ":" .. tostring(port))
end

tcpSocket.EventHandler = function(sock, evt, err)
    if evt == TcpSocket.Events.Connected then
        setStatus("Connected — querying power")
        queryPower("After connect")
    elseif evt == TcpSocket.Events.Reconnect then
        debugMsg("TCP Reconnect")
    elseif evt == TcpSocket.Events.Data then
        buf = tcpSocket:ReadLine(TcpSocket.EOL.Custom, txtEOL)
        while buf ~= nil do
            processIncomingLine(buf)
            buf = tcpSocket:ReadLine(TcpSocket.EOL.Custom, txtEOL)
        end
    elseif evt == TcpSocket.Events.Closed then
        onSocketDropped("Disconnected")
    elseif evt == TcpSocket.Events.Error then
        onSocketDropped("TCP error", "TCP Error: " .. tostring(err))
    elseif evt == TcpSocket.Events.Timeout then
        onSocketDropped(
            "TCP timeout",
            "ReadTimeout=" .. tostring(sockTimeoutRead) .. "s WriteTimeout=" .. tostring(sockTimeoutWrite) .. "s — adjust if unintended"
        )
    end
end

-------------------** Event Handlers **-------------------
if Controls.txtIPAddress then
    Controls.txtIPAddress.EventHandler = tcpConnect
end
if Controls.knbPortNumber then
    Controls.knbPortNumber.EventHandler = tcpConnect
end

Controls.btnPowerOn.EventHandler = function(ctl)
    cmdPowerOn()
    pollTransitions:Start(amtPollTime)
end

Controls.btnPowerOff.EventHandler = function(ctl)
    cmdPowerOff()
    pollTransitions:Start(amtPollTime)
end

Controls.btnPowerToggle.EventHandler = function(ctl)
    if ctl.Boolean then
        cmdPowerOn()
    else
        cmdPowerOff()
    end
end


-------------------** Init **-------------------
if Controls.knbPortNumber and Controls.knbPortNumber.Value ~= nil then
    if (Controls.knbPortNumber.Value or 0) < 1 then
        Controls.knbPortNumber.Value = tcpPort
    end
end

currentPowerState = nil
for i = 1, 4 do
    Controls.ledPowerStatus[i].Boolean = false
end
btnDisabledState(nil)
setPowerControlsFB(false)
setStatus("Projector 2000 — idle")

tcpConnect()
