--[[
    NewTek Camera Controller
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-02-11
    Firmware Req: 10.0.0
    Notes:
    - This script is a controller for NewTek cameras.
    - It is a simple controller that can be used to control the cameras.
]]

-------------------[ Runtime Options ]-------------------
local OFFLINE_MODE = true -- Set false for live camera/TCP testing
local presetSlots = 0

local function getArrayCount(tbl)
    local count = 0
    for _ in ipairs(tbl or {}) do
        count = count + 1
    end
    return count
end

-------------------[ Component References ]-------------------
local uciController = Component.New('uciController')

-------------------[ Control References ]-------------------
local controls = {
    txtIPAddress = Controls.txtIPAddress,
    knbPortNumber = Controls.knbPortNumber,
    btnPanLeft = Controls.btnPanLeft,
    btnPanRight = Controls.btnPanRight,
    btnTiltUp = Controls.btnTiltUp,
    btnTiltDown = Controls.btnTiltDown,
    btnZoomIn = Controls.btnZoomIn,
    btnZoomOut = Controls.btnZoomOut,
    btnPresetHome = Controls.btnPresetHome,
    btnCameraOn = Controls.btnCameraOn,
    btnCameraOff = Controls.btnCameraOff,
    btnCamPreset = Controls.btnCamPreset or {},
    ledPresetRecall = Controls.ledPresetRecall or {},
    ledPresetSave = Controls.ledPresetSave or {},
    knbHoldTime = Controls.knbHoldTime,
    knbLEDOnTime = Controls.knbLEDOnTime,
    txtStatus = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls,
}

local function getPresetControl(arrayControl, namedPrefix, index)
    return (arrayControl and arrayControl[index]) or Controls[namedPrefix .. " " .. index]
end

local presetBtnCount = getArrayCount(controls.btnCamPreset)
local presetRecallLedCount = getArrayCount(controls.ledPresetRecall)
local presetSaveLedCount = getArrayCount(controls.ledPresetSave)
presetSlots = math.max(presetBtnCount, presetRecallLedCount, presetSaveLedCount)

for i = 1, presetSlots do
    controls.btnCamPreset[i] = getPresetControl(controls.btnCamPreset, "btnCamPreset", i)
    controls.ledPresetRecall[i] = getPresetControl(controls.ledPresetRecall, "ledPresetRecall", i)
    controls.ledPresetSave[i] = getPresetControl(controls.ledPresetSave, "ledPresetSave", i)
end

print(
    "Preset controls detected | Buttons: " .. tostring(presetBtnCount) ..
    " | Recall LEDs: " .. tostring(presetRecallLedCount) ..
    " | Save LEDs: " .. tostring(presetSaveLedCount) ..
    " | Slots Used: " .. tostring(presetSlots)
)

-------------------[ State Tracking Tables ]-------------------
local tblbtnLongPressed = {}
local tblCountdownTimers = {}
local tblLEDTimers = {}

-------------------[ Helper Functions ]-------------------
-- Sets one preset recall LED active and turns off all others (interlock)
local function setActivePresetLED(activeIndex)
    for i = 1, presetSlots do
        if controls.ledPresetRecall[i] then
            controls.ledPresetRecall[i].Boolean = (i == activeIndex)
        end
    end
end

-- Mirror any ledPresetSave to uciController pin
local function syncUciPresetSaved()
    local pin = uciController and uciController['pinLEDPresetSaved']
    if pin then
        local on = false
        for slot = 1, presetSlots do if controls.ledPresetSave[slot] and controls.ledPresetSave[slot].Boolean then on = true break end end
        pin.Boolean = on
    end
end

-- Sends VISCA command or logs it in offline mode
local function sendVisca(cmd, label)
    if OFFLINE_MODE then
        print("[MOCK SEND] " .. (label or "VISCA command"))
        return
    end
    devCam:Write(cmd)
end

-------------------[ Create TCP Socket Connection ]-------------------
devCam = TcpSocket.New() --creates the TCP socket
--devCam:Connect("192.168.1.106",52381)
function tcpConnect()
  if OFFLINE_MODE then
    print("OFFLINE_MODE enabled: TCP connection skipped")
    return
  end

  devCam:Disconnect()--hang up the connection
  --pollLevel:Stop()
  if Controls.txtIPAddress.String ~= "" then
    devCam:Connect(Controls.txtIPAddress.String, Controls.knbPortNumber.Value)
    print("tcpConnect attempted with: ", "IP Address:"..Controls.txtIPAddress.String, "Port:"..Controls.knbPortNumber.Value)
  else
    print("tcpConnect: IP address is blank. Please enter good IP info.")
  end --if
end

tcpConnect()
controls.txtIPAddress.EventHandler = tcpConnect
controls.knbPortNumber.EventHandler = tcpConnect

devCam.EventHandler = function( sock, evt, err )
    if evt == TcpSocket.Events.Connected then
      print("devCam is Connected")
      --pollLevel:Start(2)
    elseif evt == TcpSocket.Events.Reconnect then
      print("devCam is Reconnect")
    elseif evt == TcpSocket.Events.Data then
      print("devCam is Data")
      tempStringRemovedFromBuffer = devCam:ReadLine(TcpSocket.EOL.Custom, "\r")--destructively removes from the buffer, delimeter is removed 
    --   while tempStringRemovedFromBuffer ~= nil do
    --     funcLevelParser(tempStringRemovedFromBuffer)
    --     tempStringRemovedFromBuffer = devCam:ReadLine(TcpSocket.EOL.Custom, "\r")-- if there is more than one line of response
    --   end--loop
    elseif evt == TcpSocket.Events.Closed then
      print("devCam is Closed")
      --pollLevel:Stop()                   
    elseif evt == TcpSocket.Events.Error then
      print("devCam is Error")
      --pollLevel:Stop()
    elseif evt == TcpSocket.Events.Timeout then
      print("devCam is Timeout")
      --pollLevel:Stop()
    end--if
end--tcp

-------------------[ VISCA Command Strings ]-------------------
local visca = {
    -- Pan/Tilt Commands
    tiltUp = "\x81\x01\x06\x01\x00\x07\x03\x01\xFF",
    tiltDown = "\x81\x01\x06\x01\x00\x07\x03\x02\xFF",
    panLeft = "\x81\x01\x06\x01\x09\x00\x01\x03\xFF",
    panRight = "\x81\x01\x06\x01\x09\x00\x02\x03\xFF",
    stopPanTilt = "\x81\x01\x06\x01\x00\x00\x03\x03\xFF",
    
    -- Zoom Commands
    zoomIn = "\x81\x01\x04\x07\x02\xFF",
    zoomOut = "\x81\x01\x04\x07\x03\xFF",
    stopZoom = "\x81\x01\x04\x07\x00\xFF",
    
    -- Preset Commands
    presetHome = "\x81\x01\x06\x04\xFF",
    presetRecall = {
        "\x81\x01\x04\x3F\x02\x01\xFF",
        "\x81\x01\x04\x3F\x02\x02\xFF",
        "\x81\x01\x04\x3F\x02\x03\xFF",
        "\x81\x01\x04\x3F\x02\x04\xFF"
    },
    presetSave = {
        "\x81\x01\x04\x3F\x01\x01\xFF",
        "\x81\x01\x04\x3F\x01\x02\xFF",
        "\x81\x01\x04\x3F\x01\x03\xFF",
        "\x81\x01\x04\x3F\x01\x04\xFF"
    },
    
    -- Power Commands
    camOn = "\x81\x01\x04\x00\x02\xFF",
    camOff = "\x81\x01\x04\x00\x03\xFF"
}

-------------------[ Event Handler Factories ]-------------------
-- Creates an event handler that sends a command on press and a stop command on release
local function createToggleHandler(pressCmd, releaseCmd)
    return function(ctl)
        if ctl.Boolean then
            sendVisca(pressCmd)
        else
            sendVisca(releaseCmd)
        end
    end
end

-- Creates an event handler that only sends a command on press
local function createTriggerHandler(cmd)
    return function(ctl)
        sendVisca(cmd)
    end
end

-------------------[ Camera Control Event Handlers ]-------------------
-- Pan/Tilt Controls (with stop on release)
controls.btnTiltUp.EventHandler = createToggleHandler(visca.tiltUp, visca.stopPanTilt)
controls.btnTiltDown.EventHandler = createToggleHandler(visca.tiltDown, visca.stopPanTilt)
controls.btnPanLeft.EventHandler = createToggleHandler(visca.panLeft, visca.stopPanTilt)
controls.btnPanRight.EventHandler = createToggleHandler(visca.panRight, visca.stopPanTilt)

-- Zoom Controls (with stop on release)
controls.btnZoomIn.EventHandler = createToggleHandler(visca.zoomIn, visca.stopZoom)
controls.btnZoomOut.EventHandler = createToggleHandler(visca.zoomOut, visca.stopZoom)

-- Trigger Controls (send once on press)
controls.btnPresetHome.EventHandler = createTriggerHandler(visca.presetHome)
controls.btnCameraOn.EventHandler = createTriggerHandler(visca.camOn)
controls.btnCameraOff.EventHandler = createTriggerHandler(visca.camOff)

-- Preset Controls (Press-and-Hold Logic)
for i = 1, presetSlots do
    local btnPreset = controls.btnCamPreset[i]
    local ledRecall = controls.ledPresetRecall[i]
    local ledSave = controls.ledPresetSave[i]

    if btnPreset and ledRecall and ledSave then
        tblbtnLongPressed[i] = false
        tblCountdownTimers[i] = Timer.New()
        tblLEDTimers[i] = Timer.New()

        -- When countdown timer expires during button press, it's a long press (save)
        tblCountdownTimers[i].EventHandler = function()
            tblCountdownTimers[i]:Stop()
            if btnPreset.Boolean then
                local ledOnTime = (controls.knbLEDOnTime and controls.knbLEDOnTime.Value) or 1.0
                tblbtnLongPressed[i] = true
                ledSave.Boolean = true
                syncUciPresetSaved()
                tblLEDTimers[i]:Start(ledOnTime)
            end
        end

        -- When LED flash timer expires, turn off the save LED
        tblLEDTimers[i].EventHandler = function()
            tblLEDTimers[i]:Stop()
            ledSave.Boolean = false
            syncUciPresetSaved()
        end

        -- Button press/release handler
        btnPreset.EventHandler = function(ctl)
            if ctl.Boolean then
                local holdTime = (controls.knbHoldTime and controls.knbHoldTime.Value) or 2.0
                tblbtnLongPressed[i] = false
                tblCountdownTimers[i]:Start(holdTime)
            else
                tblCountdownTimers[i]:Stop()
                if tblbtnLongPressed[i] then
                    sendVisca(visca.presetSave[i], "Preset Save " .. i)
                    print("Saved Preset[" .. i .. "]")
                    setActivePresetLED(i)
                else
                    sendVisca(visca.presetRecall[i], "Preset Recall " .. i)
                    print("Recalled Preset[" .. i .. "]")
                    setActivePresetLED(i)
                end
                tblbtnLongPressed[i] = false
            end
        end
    else
        print("Preset slot " .. i .. " missing one or more controls; skipping handler setup")
    end
end
  
