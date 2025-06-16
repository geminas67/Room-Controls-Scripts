--[[ 

  System Automation Helper Script
  Author: Hope Roth, Q-SYS
  February, 2025
  Firmware Req: 9.12
  Version: 1.0
  
  ]] --

--------** Constant Tables **--------

compDisplays = {} -- list of all display control components
compInvalid = {} -- table containing all components that are currently invalid

--------** Constants **--------

Debugging = true -- set to true in order to print funcDebug statements
ClearString = "[Clear]" -- string used in combo boxes to clear out a component

MotionChoices = {"Motion On/Off", "Motion Off", "Motion Disabled"}

MotionTimer = Timer.New() -- the additional timeout period after the motion sensor goes low
GraceTimer = Timer.New() -- the timeout period after turning the system off where the motion sensor won't turn the system on
WarmupTimer = Timer.New() -- the time it takes the system to warm up, power controls will lock out during this time.
CooldownTimer = Timer.New() -- the time it takes the system to cool down, power controls will lock out during this time.

--------** Functions **--------

--------## Setup ##--------
function funcDebug(str) -- helper function that prints funcDebug statements when enabled
    if Debugging then
        print("[funcDebug] " .. str)
    end
end

--------## Notifications ##--------

function funcPublishNotification()
    SystemState = {
      PowerState = Controls.SystemPower.Boolean,
      SystemWarming = Controls.SystemWarming.Boolean,
      SystemCooling = Controls.SystemCooling.Boolean,
      AudioPrivacy = Controls.btnAudioPrivacy.Boolean,
      VideoPrivacy = Controls.btnVideoPrivacy.Boolean,
      VolumeLvl = Controls.VolumeFader.Position,
      VolumeMute = Controls.VolumeMute.Boolean
    }
    Notifications.Publish(Controls.NotificationId.String, SystemState)
end

--------## System Components ##--------

function funcGetComponentNames()
    -- table to hold component names
    local NamesTable = {
        -- multi-dimensional table to store different component names
        CallSyncNames = {}, -- call sync blocks
        VideoBridgeNames = {}, -- video bridge blocks
        DisplayNames = {}, -- display plugin blocks
        GainNames = {}, -- gain blocks
        MuteNames = {} -- system mute blocks
    }

    -- gather component names
    for i, v in pairs(Component.GetComponents()) do
        --print(i, v.Name, v.Type)
        if v.Type == "call_sync" then -- call sync
            table.insert(NamesTable.CallSyncNames, v.Name)
        elseif v.Type == "usb_uvc" then -- video bridge
            table.insert(NamesTable.VideoBridgeNames, v.Name)
        elseif v.Type == "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_17f7c2b905c38a7cdf412359a2a9a848" then -- generic display plugin
            table.insert(NamesTable.DisplayNames, v.Name)
        elseif v.Type == "gain" then -- call sync
            table.insert(NamesTable.GainNames, v.Name)
        elseif v.Type == "system_mute" then -- PSO Display Control Helper
            table.insert(NamesTable.MuteNames, v.Name)
        end
    end

    for i, v in pairs(NamesTable) do -- iterate through our tables of tables, format them for our combo boxes
        table.sort(v) -- sort alphabetically
        table.insert(v, ClearString) -- add "[clear]" to the end
    end

    -- set script choices
    Controls.compCallSync.Choices = NamesTable.CallSyncNames
    Controls.compVideoBridge.Choices = NamesTable.VideoBridgeNames

    for i, v in ipairs(Controls.devDisplays) do
        v.Choices = NamesTable.DisplayNames
    end

    Controls.compProgramVolume.Choices = NamesTable.GainNames
    Controls.compSystemMute.Choices = NamesTable.MuteNames
end

function funcCheckStatus()
    for i, v in pairs(compInvalid) do
        if v == true then -- we found
            --funcDebug("There is at Least One Invalid Component")
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    --funcDebug("No Invalid Components Found")
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

function funcSetcompInvalid(componentType)
    compInvalid[componentType] = true
    funcCheckStatus()
end

function funcSetcompValid(componentType)
    compInvalid[componentType] = false
    funcCheckStatus()
end

function funcSetcomp(ctrl, componentType) -- a helper function that maps components to user selections
    funcDebug("Setting Component: " .. componentType)
    componentName = ctrl.String
    if componentName == "" then -- no component selected
        funcDebug("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        funcSetcompValid(componentType)
        return nil
    elseif componentName == ClearString then -- component has been cleared by the user
        funcDebug(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        funcSetcompValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then -- invalid component
        funcDebug(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        funcSetcompInvalid(componentType)
        return nil
    else -- great success!
        funcDebug("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = "white"
        funcSetcompValid(componentType)
        return Component.New(componentName)
    end--if
end--func

---- Call Sync and Video Privacy ----

function funcSetcompCallSync()
    compCallSync = funcSetcomp(Controls.compCallSync, "Call Sync")
    if compCallSync ~= nil then -- success!
        compCallSync["off.hook"].EventHandler = funcCallSyncCheckConnection -- attach event handler to system being in a call
        compCallSync["mute"].EventHandler = funcCallSyncCheckMute -- attach event handler to call sync privacy
    end--if
end--func

function funcCallSyncCheckMute() -- helper function that sets the mute state of the call sync block
    if compCallSync ~= nil then
        local state = compCallSync["mute"].Boolean
        funcDebug("Call Sync Mute State is: " .. tostring(state))
        Controls.btnAudioPrivacy.Boolean = state
    end--if
end--func

function funcSetCallSyncMute(state) -- helper function that sets the mute state of the call sync block
    if compCallSync ~= nil then
        funcDebug("Setting Call Sync Mute: " .. tostring(state))
        compCallSync["mute"].Boolean = state
    end--if
    Controls.btnAudioPrivacy.Boolean = state
    funcPublishNotification()
end--func

function funcCallSyncEnd(state) -- helper function that ends all calls using the call sync block
    if compCallSync ~= nil then
        funcDebug("Ending Calls")
        compCallSync["call.decline"]:Trigger() -- end calls
    end--if
end--func

function funcSetcompVideoBridge()
    compVideoBridge = funcSetcomp(Controls.compVideoBridge, "Video Bridge")
    if compVideoBridge ~= nil then -- success!
        compVideoBridge["toggle.privacy"].EventHandler = funcGetVideoPrivacyState -- attach event handler to system being in a call
    end--if
end--func

function funcGetVideoPrivacyState()
    if compVideoBridge ~= nil then
        local state = compVideoBridge["toggle.privacy"].Boolean
        funcDebug("Video Privacy State is: " .. tostring(state))
        Controls.btnVideoPrivacy.Boolean = state
        funcPublishNotification()
    end--if
end--func

function funcSetVideoPrivacy(state)
    if compVideoBridge ~= nil then
        funcDebug("Setting Video Privacy: " .. tostring(state))
        compVideoBridge["toggle.privacy"].Boolean = state
    end--if
    Controls.btnVideoPrivacy.Boolean = state
    funcPublishNotification()
end--func

---- Displays ----

function funcSetcompDisplay(idx)
    compDisplays[idx] = funcSetcomp(Controls.devDisplays[idx], "Display [" .. idx .. "]")
    if compDisplays[idx] ~= nil then -- success!
    end--if
end--func

function funcSetcompDisplayOn(display)
    if btnDisplay["PowerOnTrigger"] then -- check for valid component control
        --funcDebug("Turning On Display")
        btnDisplay["PowerOnTrigger"]:Trigger()
    end--if
end--func

function funcSetcompDisplayOff(display)
    if btnDisplay["PowerOffTrigger"] then -- check for valid component control
        --funcDebug("Turning Off Display")
        btnDisplay["PowerOffTrigger"]:Trigger()
    end--if
end--func

function funcSetcompDisplayPower(state)
    for i, v in pairs(compDisplays) do -- iterate through display components, using pairs because some might be nil
        if state then
            -- funcDebug("Turning Displays On")
            funcSetcompDisplayOn(v)
        else
            -- funcDebug("Turning Displays Off")
            funcSetcompDisplayOff(v)
        end--if
    end--for
end--func

---- Motion ----

function funcCheckMotion()
    funcDebug("Checking Motion")
    if Controls.MotionIn.Boolean then -- is there motion in the space?
        Controls.MotionTimeoutActive.Boolean = false
        MotionTimer:Stop() -- stop the motion timeout
        if
            not Controls.SystemPower.Boolean and not Controls.MotionGraceActive.Boolean and
                Controls.MotionMode.String=="Motion On/Off"
         then -- turn system on if the system is off, and motion on is enabled
            funcDebug("Turning System on from Motion")
            funcSystemPowerOn()
        end--if
    else -- no motion in the space
        if Controls.MotionMode.String=="Motion On/Off" or Controls.MotionMode.String=="Motion Off" then -- system off from no motion
            funcDebug("Starting Motion Off Timer")
            Controls.MotionTimeoutActive.Boolean = true
            MotionTimer:Start(Controls.MotionTimeout.Value) -- start motion timeout from user value
        end--if
    end--if
end--func

---- System Mute ----

function funcSetcompMutePGM()
    SystemMute = funcSetcomp(Controls.compSystemMute, "System Mute")
    if SystemMute ~= nil then -- success!
    end--if
end--func

function funcSetcompSystemMute(state) -- mute all audio in the system using the system mute block
    if SystemMute ~= nil then
        --funcDebug("Setting System Mute")
        SystemMute["mute"].Boolean = state
    end--if
end--func
---- Volume ----

function funcSetGainLvlVisualFeedback()
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

function funcSetcompGainPGM()
    ProgramVolume = funcSetcomp(Controls.compProgramVolume, "Program Volume")
    if ProgramVolume ~= nil then -- success!
        GetVolumeLvl()
        GetVolumeMute()
        ProgramVolume["gain"].EventHandler = GetVolumeLvl
        ProgramVolume["mute"].EventHandler = GetVolumeMute

        Controls.VolumeFader.EventHandler = SetVolumeLvl

        Controls.VolumeMute.EventHandler = function(ctl)
          SetVolumeMute(ctl.Boolean)
        end--EH 

        Controls.VolumeUpDown[1].EventHandler = function(ctl)
            funcSetVolumeUpDown("stepper.increase", ctl.Boolean)
        end--EH 
        
        Controls.VolumeUpDown[2].EventHandler = function(ctl)
            funcSetVolumeUpDown("stepper.decrease", ctl.Boolean)
        end--EH 
    end--if
end--func

function funcSetDefaultAudioLvl()
    if ProgramVolume ~= nil and ProgramVolume["gain"] ~= nil then
        funcDebug("Setting Volume Percentage to: " .. Controls.DefaultVolume.Position)
        ProgramVolume["gain"].Position = Controls.DefaultVolume.Position
    end--if
end--func

function GetVolumeLvl()
    if ProgramVolume ~= nil then
        Controls.VolumeFader.Position = ProgramVolume["gain"].Position
        funcSetGainLvlVisualFeedback()
        funcPublishNotification()
    end--if
end--func

function GetVolumeMute()
    if ProgramVolume ~= nil then
        Controls.VolumeMute.Boolean = ProgramVolume["mute"].Boolean
        funcSetGainLvlVisualFeedback()
        funcPublishNotification()
    end--if
end--func

function SetVolumeLvl()
    if ProgramVolume ~= nil then
        ProgramVolume["gain"].Position = Controls.VolumeFader.Position
        funcSetGainLvlVisualFeedback()
        funcPublishNotification()
    end--if
end--func

function SetVolumeMute(state)
    if ProgramVolume ~= nil then
        ProgramVolume["mute"].Boolean = state
        funcSetGainLvlVisualFeedback()
        funcPublishNotification()
    end--if
end--func

function funcSetVolumeUpDown(ctrl, state)
    if ProgramVolume ~= nil then
        ProgramVolume[ctrl].Boolean = state
    end--if
end--func

--------## System Power ##--------
function funcEnableDisablePowerControls(state)
    Controls.SystemOnOff.IsDisabled = not state
    Controls.SystemOn.IsDisabled = not state
    Controls.SystemOff.IsDisabled = not state
end--func

function funcSetSystemPowerFB(state)
    Controls.SystemPower.Boolean = state -- update system power LED FB
    Controls.SystemOnOff.Boolean = state -- update system power toggle FB
    Controls.SystemOn.Boolean = state -- update system power on state trigger FB
    Controls.SystemOff.Boolean = not state -- update system power off state trigger FB
end--func

function funcSystemPowerOn(route) -- turn system on
    funcDebug("Powering System On")
    Controls.SystemOnTrig:Trigger()
    funcEnableDisablePowerControls(false) -- disable power controls
    Controls.SystemWarming.Boolean = true -- system is warming
    WarmupTimer:Start(Controls.WarmupTime.Value) -- start timer for warming fb
    funcSetSystemPowerFB(true) -- update system power feedback
    -- funcSetcompSystemMute(false) -- system mute off
    funcSetDefaultAudioLvl() -- set system gain to default level
    funcSetCallSyncMute(true) -- audio privacy on
    funcSetVideoPrivacy(false) -- video privacy off
    funcSetcompDisplayPower(true) -- turn dispays on
    funcPublishNotification() -- send out notification with current system state
end--func

function funcSystemPowerOff() -- turn system off
    funcDebug("Powering System Off")
    Controls.SystemOffTrig:Trigger()
    funcEnableDisablePowerControls(false) -- disable power controls
    Controls.SystemCooling.Boolean = true -- system is cooling
    CooldownTimer:Start(Controls.CooldownTime.Value) -- start timer for cooling fb
    funcSetSystemPowerFB(false) -- update system power feedback
    -- funcSetcompSystemMute(true) -- system mute on
    funcSetCallSyncMute(true) -- audio privacy on
    funcSetVideoPrivacy(true) --video privacy on
    funcSetcompDisplayPower(false) -- displays off
    funcCallSyncEnd(false) -- send calls
    funcPublishNotification() -- send out notification with current system state
end--func

-------- Fire Alarm --------

function funcSetFireAlarm(state)
    if state then -- fire alarm start
        funcSetcompSystemMute(true) -- system mute on
        funcSetcompDisplayPower(false) -- shut off displays
    else -- fire alarm end
        if Controls.SystemPower.Boolean then -- system was on, so
            funcSetcompSystemMute(false) -- system mute off
            funcSetcompDisplayPower(true) -- turn displays back on
        end--if
    end--if
end--func

-------- Event Handlers --------

MotionTimer.EventHandler = function()
    -- trigger system off after timeout period ends
    funcDebug("Motion Timeout")
    Controls.MotionTimeoutActive.Boolean = false
    MotionTimer:Stop()
    funcSystemPowerOff()
end--EH

GraceTimer.EventHandler = function()
    -- allow system to power on from motion after grace period ends
    funcDebug("Grace Period Has Ended")
    Controls.MotionGraceActive.Boolean = false
    GraceTimer:Stop()
end--EH

WarmupTimer.EventHandler = function()
    --re-enable power buttons after warmup period ends
    funcDebug("Warmup Period Has Ended")
    Controls.SystemWarming.Boolean = false
    funcEnableDisablePowerControls(true)
    WarmupTimer:Stop()
    funcPublishNotification() -- publish notification of current system state
end--EH

CooldownTimer.EventHandler = function()
    --re-enable power buttons after cooldown period ends
    funcDebug("Cooldown Period Has Ended")
    Controls.SystemCooling.Boolean = false
    funcEnableDisablePowerControls(true)
    CooldownTimer:Stop()
    funcPublishNotification() -- publish notification of current system state
end--EH

Controls.SystemOnOff.EventHandler = function(ctl) -- event handler for on/off toggle
    if ctl.Boolean then -- system on
        funcSystemPowerOn()
    else
        funcSystemPowerOff()
    end--if
end--EH

Controls.SystemOff.EventHandler = function()
    funcSystemPowerOff()
    -- trigger system off
    Controls.MotionGraceActive.Boolean = true -- enable grace period
    GraceTimer:Start(Controls.MotionGracePeriod.Value) -- start grace timer
end--EH

Controls.SystemOn.EventHandler = function()
    -- trigger system on
    funcSystemPowerOn()
end--EH

Controls.btnAudioPrivacy.EventHandler = function(ctl) -- set audio privacy to button state
    funcSetCallSyncMute(ctl.Boolean)
end--EH

Controls.btnVideoPrivacy.EventHandler = function(ctl) -- set video privacy to button state
    funcSetVideoPrivacy(ctl.Boolean)
end--EH

-- change in control component selections
Controls.compCallSync.EventHandler = funcSetcompCallSync
Controls.compVideoBridge.EventHandler = funcSetcompVideoBridge
Controls.MotionIn.EventHandler = funcCheckMotion
Controls.compSystemMute.EventHandler = funcSetcompMutePGM
Controls.compProgramVolume.EventHandler = funcSetcompGainPGM

for i, v in ipairs(Controls.devDisplays) do
    v.EventHandler = function()
        funcSetcompDisplay(i)
    end--EH
end--for

-------- Always Run --------
function funcInit()
    funcEnableDisablePowerControls(true) --enable power controls
    funcGetVideoPrivacyState() --sync video privacy fb
    funcGetComponentNames() -- populate combo boxes for component selection with script names

    Controls.MotionMode.Choices = MotionChoices -- fill in combo boxes with motion control options

    -- set components with what's currently selected 
    funcSetcompCallSync() 
    funcSetcompVideoBridge()
    funcSetcompGainPGM()
    funcSetcompMutePGM()
    for i, v in ipairs(Controls.devDisplays) do
        funcSetcompDisplay(i)
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
