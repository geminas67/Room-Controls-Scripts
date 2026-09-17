--[[ 

  System Automation Helper Script
  Author: Hope Roth, Q-SYS
  February, 2025
  Firmware Req: 9.12
  Version: 1.0
  
  ]] --

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync    = "call_sync",
  videoBridge = "usb_uvc",
  display     = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_17f7c2b905c38a7cdf412359a2a9a848",
  gain        = "gain",
  systemMute  = "system_mute",
}

MotionChoices = {"Motion On/Off", "Motion Off", "Motion Disabled"}

-------------------[ Constant Tables ]-------------------

compDisplays = {} -- list of all display control components
compInvalid = {} -- table containing all components that are currently invalid
compCallSync = nil
compVideoBridge = nil
SystemMute = nil
ProgramVolume = nil

-------------------[ Constants ]-------------------

stateDebug = true -- set to true in order to print debugMsg statements
strClear = "[Clear]" -- string used in combo boxes to clear out a component

timerMotion     = Timer.New() -- the additional timeout period after the motion sensor goes low
timerGrace      = Timer.New() -- the timeout period after turning the system off where the motion sensor won't turn the system on
timerWarmup     = Timer.New() -- the time it takes the system to warm up, power controls will lock out during this time.
timerCooldown   = Timer.New() -- the time it takes the system to cool down, power controls will lock out during this time.

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------
function debugMsg(str) -- helper function that prints debugMsg statements when enabled
    if stateDebug then
        print("[debugMsg] " .. str)
    end
end

-------------------[ Notifications ]-------------------

function publishNotification()
    systemState = {
      PowerState    = Controls.SystemPower.Boolean,
      SystemWarming = Controls.SystemWarming.Boolean,
      SystemCooling = Controls.SystemCooling.Boolean,
      AudioPrivacy  = Controls.btnAudioPrivacy.Boolean,
      VideoPrivacy  = Controls.btnVideoPrivacy.Boolean,
      VolumeLvl     = Controls.VolumeFader.Position,
      VolumeMute    = Controls.VolumeMute.Boolean
    }
    Notifications.Publish(Controls.NotificationId.String, systemState)
end

-------------------[ Discovery ]-------------------

function getComponentNames()
    -- table to hold component names
    local NamesTable = {
        -- multi-dimensional table to store different component names
        CallSyncNames = {},     -- call sync blocks
        VideoBridgeNames = {},  -- video bridge blocks
        DisplayNames = {},      -- display plugin blocks
        GainNames = {},         -- gain blocks
        MuteNames = {}          -- system mute blocks
    }

    -- gather component names
    for i, comp in pairs(Component.GetComponents()) do
        --print(i, comp.Name, comp.Type)
        if comp.Type == componentTypes.callSync then
            table.insert(NamesTable.CallSyncNames, comp.Name)
        elseif comp.Type == componentTypes.videoBridge then
            table.insert(NamesTable.VideoBridgeNames, comp.Name)
        elseif comp.Type == componentTypes.display then
            table.insert(NamesTable.DisplayNames, comp.Name)
        elseif comp.Type == componentTypes.gain then
            table.insert(NamesTable.GainNames, comp.Name)
        elseif comp.Type == componentTypes.systemMute then
            table.insert(NamesTable.MuteNames, comp.Name)
        end
    end

    for i, tbl in pairs(NamesTable) do -- iterate through our tables of tables, format them for our combo boxes
        table.sort(tbl) -- sort alphabetically
        table.insert(tbl, strClear) -- add "[clear]" to the end
    end

    -- set script choices
    Controls.compCallSync.Choices = NamesTable.CallSyncNames
    Controls.compVideoBridge.Choices = NamesTable.VideoBridgeNames

    for i, ctl in ipairs(Controls.devDisplays) do
        ctl.Choices = NamesTable.DisplayNames
    end

    Controls.compProgramVolume.Choices = NamesTable.GainNames
    Controls.compSystemMute.Choices = NamesTable.MuteNames
end

-------------------[ Status ]-------------------

function getStatus()
    for i, v in pairs(compInvalid) do
        if v == true then -- we found
            debugMsg("There is at least one Invalid Component")
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    --debugMsg("No Invalid Components Found")
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

function setCompInvalid(componentType)
    compInvalid[componentType] = true
    getStatus()
end

function setCompValid(componentType)
    compInvalid[componentType] = false
    getStatus()
end

function setComp(ctl, componentType) -- a helper function that maps components to user selections
    debugMsg("Setting Component: " .. componentType)
    componentName = ctl.String
    if componentName == "" then -- no component selected
        debugMsg("No " .. componentType .. " Component Selected")
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    elseif componentName == strClear then -- component has been cleared by the user
        debugMsg(componentType .. ": Component Cleared")
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then -- invalid component
        debugMsg(componentType .. " Component " .. componentName .. " is Invalid")
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        return nil
    else -- great success!
        debugMsg("Setting " .. componentType .. " Component: {" .. ctl.String .. "}")
        ctl.Color = "white"
        setCompValid(componentType)
        return Component.New(componentName)
    end--if
end--func

-------------------[ Components ]-------------------

function setcompCallSync()
    compCallSync = setComp(Controls.compCallSync, "Call Sync")
    if compCallSync ~= nil then -- success!
        compCallSync["off.hook"].EventHandler = funcCallSyncCheckConnection -- attach event handler to system being in a call
        compCallSync["mute"].EventHandler = getCallSyncMute -- attach event handler to call sync privacy
    end--if
end--func

function getCallSyncMute() -- helper function that sets the mute state of the call sync block
    if compCallSync ~= nil then
        local state = compCallSync["mute"].Boolean
        debugMsg("Call Sync Mute State is: " .. tostring(state))
        Controls.btnAudioPrivacy.Boolean = state
    end--if
end--func

function setCallSyncMute(state) -- helper function that sets the mute state of the call sync block
    if compCallSync ~= nil then
        debugMsg("Setting Call Sync Mute: " .. tostring(state))
        compCallSync["mute"].Boolean = state
    end--if
    Controls.btnAudioPrivacy.Boolean = state
    publishNotification()
end--func

function endCalls(state) -- helper function that ends all calls using the call sync block
    if compCallSync ~= nil then
        debugMsg("Ending Calls")
        compCallSync["call.decline"]:Trigger() -- end calls
    end--if
end--func

function setcompVideoBridge()
    compVideoBridge = setComp(Controls.compVideoBridge, "Video Bridge")
    if compVideoBridge ~= nil then -- success!
        compVideoBridge["toggle.privacy"].EventHandler = getVideoPrivacyState -- attach event handler to system being in a call
    end--if
end--func

function getVideoPrivacyState()
    if compVideoBridge ~= nil then
        local state = compVideoBridge["toggle.privacy"].Boolean
        debugMsg("Video Privacy State is: " .. tostring(state))
        Controls.btnVideoPrivacy.Boolean = state
        publishNotification()
    end--if
end--func

function setVideoPrivacy(state)
    if compVideoBridge ~= nil then
        debugMsg("Setting Video Privacy: " .. tostring(state))
        compVideoBridge["toggle.privacy"].Boolean = state
    end--if
    Controls.btnVideoPrivacy.Boolean = state
    publishNotification()
end--func

-------------------[ Displays ]-------------------

function setcompDisplay(idx)
    compDisplays[idx] = setComp(Controls.devDisplays[idx], "Display [" .. idx .. "]")
    if compDisplays[idx] ~= nil then -- success!
    end--if
end--func

function setcompDisplayOn(display)
    if btnDisplay["PowerOnTrigger"] then -- check for valid component control
        --debugMsg("Turning On Display")
        btnDisplay["PowerOnTrigger"]:Trigger()
    end--if
end--func

function setcompDisplayOff(display)
    if btnDisplay["PowerOffTrigger"] then -- check for valid component control
        --debugMsg("Turning Off Display")
        btnDisplay["PowerOffTrigger"]:Trigger()
    end--if
end--func

function setcompDisplayPower(state)
    for i, v in pairs(compDisplays) do -- iterate through display components, using pairs because some might be nil
        if state then
            -- debugMsg("Turning Displays On")
            setcompDisplayOn(v)
        else
            -- debugMsg("Turning Displays Off")
            setcompDisplayOff(v)
        end--if
    end--for
end--func

-------------------[ Motion ]-------------------

function getMotion()
    debugMsg("Checking Motion")
    if Controls.MotionIn.Boolean then -- is there motion in the space?
        Controls.MotionTimeoutActive.Boolean = false
        timerMotion:Stop() -- stop the motion timeout
        if
            not Controls.SystemPower.Boolean and not Controls.MotionGraceActive.Boolean and
                Controls.MotionMode.String=="Motion On/Off"
         then -- turn system on if the system is off, and motion on is enabled
            debugMsg("Turning System on from Motion")
            setSystemPowerOn()
        end--if
    else -- no motion in the space
        if Controls.MotionMode.String=="Motion On/Off" or Controls.MotionMode.String=="Motion Off" then -- system off from no motion
            debugMsg("Starting Motion Off Timer")
            Controls.MotionTimeoutActive.Boolean = true
            timerMotion:Start(Controls.MotionTimeout.Value) -- start motion timeout from user value
        end--if
    end--if
end--func

-------------------[ System Mute ]-------------------

function setcompMutePGM()
    SystemMute = setComp(Controls.compSystemMute, "System Mute")
    if SystemMute ~= nil then -- success!
    end--if
end--func

function setCompSystemMute(state) -- mute all audio in the system using the system mute block
    if SystemMute ~= nil then
        --debugMsg("Setting System Mute")
        SystemMute["mute"].Boolean = state
    end--if
end--func
-------------------[ Volume ]-------------------

function setGainVisualFeedback()
    -- Check if volume fader is at position 0 OR if mute is explicitly set to true
    if Controls.VolumeFader.Position == 0 or Controls.VolumeMute.Boolean == true then
        -- Active (Muted) State
        Controls.VolumeFader.Color = "#CCCCCC"
        Controls.VolumeMute.CssClass = "icon-volume_off"
    else
        -- Not Active (Unmuted) State  
        Controls.VolumeFader.Color = "#0561A5"
        Controls.VolumeMute.CssClass = "icon-volume_mute"
    end--if
end--func

function setcompGainPGM()
    ProgramVolume = setComp(Controls.compProgramVolume, "Program Volume")
    if ProgramVolume ~= nil then -- success!
        getVolumeLvl()
        getVolumeMute()
        ProgramVolume["gain"].EventHandler = getVolumeLvl
        ProgramVolume["mute"].EventHandler = getVolumeMute

        Controls.VolumeFader.EventHandler = setVolumeLvl

        Controls.VolumeMute.EventHandler = function(ctl)
          setVolumeMute(ctl.Boolean)
        end--EH 

        Controls.VolumeUpDown[1].EventHandler = function(ctl)
            setVolumeUpDown("stepper.increase", ctl.Boolean)
        end--EH 
        
        Controls.VolumeUpDown[2].EventHandler = function(ctl)
            setVolumeUpDown("stepper.decrease", ctl.Boolean)
        end--EH 
    end--if
end--func

function setDefaultAudioLvl()
    if ProgramVolume ~= nil and ProgramVolume["gain"] ~= nil then
        debugMsg("Setting Volume Percentage to: " .. Controls.DefaultVolume.Position)
        ProgramVolume["gain"].Position = Controls.DefaultVolume.Position
    end--if
end--func

function getVolumeLvl()
    if ProgramVolume ~= nil then
        Controls.VolumeFader.Position = ProgramVolume["gain"].Position
        setGainVisualFeedback()
        publishNotification()
    end--if
end--func

function getVolumeMute()
    if ProgramVolume ~= nil then
        Controls.VolumeMute.Boolean = ProgramVolume["mute"].Boolean
        setGainVisualFeedback()
        publishNotification()
    end--if
end--func

function setVolumeLvl()
    if ProgramVolume ~= nil then
        ProgramVolume["gain"].Position = Controls.VolumeFader.Position
        setGainVisualFeedback()
        publishNotification()
    end--if
end--func

function setVolumeMute(state)
    if ProgramVolume ~= nil then
        ProgramVolume["mute"].Boolean = state
        setGainVisualFeedback()
        publishNotification()
    end--if
end--func

function setVolumeUpDown(ctrl, state)
    if ProgramVolume ~= nil then
        ProgramVolume[ctrl].Boolean = state
    end--if
end--func

-------------------[ System Power ]-------------------
function setEnableDisablePowerControls(state)
    Controls.btnSystemOnOff.IsDisabled = not state
    Controls.btnSystemOn.IsDisabled = not state
    Controls.btnSystemOff.IsDisabled = not state
end--func

function setSystemPowerFB(state)
    Controls.SystemPower.Boolean = state -- update system power LED FB
    Controls.btnSystemOnOff.Boolean = state -- update system power toggle FB
    Controls.btnSystemOn.Boolean = state -- update system power on state trigger FB
    Controls.btnSystemOff.Boolean = not state -- update system power off state trigger FB
end--func

function setSystemPowerOn(route) -- turn system on
    debugMsg("Powering System On")
    Controls.SystemOnTrig:Trigger()
    setEnableDisablePowerControls(false) -- disable power controls
    Controls.SystemWarming.Boolean = true -- system is warming
    timerWarmup:Start(Controls.WarmupTime.Value) -- start timer for warming fb
    setSystemPowerFB(true) -- update system power feedback
    -- setCompSystemMute(false) -- system mute off
    setDefaultAudioLvl() -- set system gain to default level
    setCallSyncMute(true) -- audio privacy on
    setVideoPrivacy(false) -- video privacy off
    setcompDisplayPower(true) -- turn dispays on
    publishNotification() -- send out notification with current system state
end--func

function setSystemPowerOff() -- turn system off
    debugMsg("Powering System Off")
    Controls.btnSystemOffTrig:Trigger()
    setEnableDisablePowerControls(false) -- disable power controls
    Controls.SystemCooling.Boolean = true -- system is cooling
    timerCooldown:Start(Controls.CooldownTime.Value) -- start timer for cooling fb
    setSystemPowerFB(false) -- update system power feedback
    -- setCompSystemMute(true) -- system mute on
    setCallSyncMute(true) -- audio privacy on
    setVideoPrivacy(true) --video privacy on
    setcompDisplayPower(false) -- displays off
    endCalls(false) -- send calls
    publishNotification() -- send out notification with current system state
end--func

-------------------[ Fire Alarm ]-------------------

function setFireAlarm(state)
    if state then -- fire alarm start
        setCompSystemMute(true) -- system mute on
        setcompDisplayPower(false) -- shut off displays
    else -- fire alarm end
        if Controls.SystemPower.Boolean then -- system was on, so
            setCompSystemMute(false) -- system mute off
            setcompDisplayPower(true) -- turn displays back on
        end--if
    end--if
end--func

-------------------[ Event Handlers ]-------------------

timerMotion.EventHandler = function()
    -- trigger system off after timeout period ends
    debugMsg("Motion Timeout")
    Controls.MotionTimeoutActive.Boolean = false
    timerMotion:Stop()
    setSystemPowerOff()
end--EH

timerGrace.EventHandler = function()
    -- allow system to power on from motion after grace period ends
    debugMsg("Grace Period Has Ended")
    Controls.MotionGraceActive.Boolean = false
    timerGrace:Stop()
end--EH

timerWarmup.EventHandler = function()
    --re-enable power buttons after warmup period ends
    debugMsg("Warmup Period Has Ended")
    Controls.SystemWarming.Boolean = false
    setEnableDisablePowerControls(true)
    timerWarmup:Stop()
    publishNotification() -- publish notification of current system state
end--EH

timerCooldown.EventHandler = function()
    --re-enable power buttons after cooldown period ends
    debugMsg("Cooldown Period Has Ended")
    Controls.SystemCooling.Boolean = false
    setEnableDisablePowerControls(true)
    timerCooldown:Stop()
    publishNotification() -- publish notification of current system state
end--EH

Controls.btnSystemOnOff.EventHandler = function(ctl) -- event handler for on/off toggle
    if ctl.Boolean then -- system on
        setSystemPowerOn()
    else
        setSystemPowerOff()
    end--if
end--EH

Controls.btnSystemOff.EventHandler = function()
    setSystemPowerOff()
    -- trigger system off
    Controls.MotionGraceActive.Boolean = true -- enable grace period
    timerGrace:Start(Controls.MotionGracePeriod.Value) -- start grace timer
end--EH

Controls.btnSystemOn.EventHandler = function()
    -- trigger system on
    setSystemPowerOn()
end--EH

Controls.btnAudioPrivacy.EventHandler = function(ctl) -- set audio privacy to button state
    setCallSyncMute(ctl.Boolean)
end--EH

Controls.btnVideoPrivacy.EventHandler = function(ctl) -- set video privacy to button state
    setVideoPrivacy(ctl.Boolean)
end--EH

-- change in control component selections
Controls.compCallSync.EventHandler      = setcompCallSync
Controls.compVideoBridge.EventHandler   = setcompVideoBridge
Controls.MotionIn.EventHandler          = getMotion
Controls.compSystemMute.EventHandler    = setcompMutePGM
Controls.compProgramVolume.EventHandler = setcompGainPGM

for i, v in ipairs(Controls.devDisplays) do
    v.EventHandler = function()
        setcompDisplay(i)
    end--EH
end--for

-------------------[ Always Run ]-------------------
function funcInit()
    setEnableDisablePowerControls(true) --enable power controls
    getVideoPrivacyState() --sync video privacy fb
    getComponentNames() -- populate combo boxes for component selection with script names

    Controls.MotionMode.Choices = MotionChoices -- fill in combo boxes with motion control options

    -- set components with what's currently selected 
    setcompCallSync() 
    setcompVideoBridge()
    setcompGainPGM()
    setcompMutePGM()
    for i, v in ipairs(Controls.devDisplays) do
        setcompDisplay(i)
    end--for
end--func

funcInit()
--[[
  
Script Copyright 2025 QSC

--Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), 
--to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
--and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

--The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
IN THE SOFTWARE. 

]] --
