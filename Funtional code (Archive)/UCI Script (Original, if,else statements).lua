--QSsys Template UCI Script
-----------------------------------------------------------------------------------------------------------------
-- Named Components
-----------------------------------------------------------------------------------------------------------------
--set the name of the component to be controlled in UCI Variables box
function funcSetcodenameNV32()
  devNV32 = Component.New(Uci.Variables.codenameNV32.String)
end
Uci.Variables.codenameNV32.EventHandler = funcSetcodenameNV32

function funcSetcodenameCamPresetCtrl()
  compNCPreset = Component.New(Uci.Variables.codenameCamPresetCtrl.String)
end
Uci.Variables.codenameCamPresetCtrl.EventHandler = funcSetcodenameCamPresetCtrl

lvlPGM = Component.New("lvlPGM-02")
-----------------------------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------------------------
--UCI Page Name
kUCIPage = "UCI MPR(005)"

---- UCI Layers
kLayer_Initialize = 1
kLayer_IncomingCall = 2
kLayer_Start = 3
kLayer_Warming = 4
kLayer_Cooling = 5
kLayer_RoomControls = 6
kLayer_PC = 7
kLayer_Laptop = 8
kLayer_Wireless = 9
kLayer_Routing = 10
kLayer_Dialer = 11

varActiveLayer = kLayer_Start
-----------------------------------------------------------------------------------------------------------------
-- Functions
-----------------------------------------------------------------------------------------------------------------
-- Set default values for animation durations
function funcSetTimeProgress()
  timeProgWarming = Uci.Variables["timeProgressWarming"] or "10"
  timeProgCooling = Uci.Variables["timeProgressCooling"] or "5"
end

function funcHideBaseLayers()
    Uci.SetLayerVisibility( kUCIPage, "X01-ProgramVolume", false , "none" )
    Uci.SetLayerVisibility( kUCIPage, "Y01-Navbar", false , "none" )
    Uci.SetLayerVisibility( kUCIPage, "Z01-Base", false , "none" )
    print("funcHideBaseLayers set")
end--func

function funcCallActivePopup()
  if Controls.pinCallActive.Boolean then 
    Uci.SetLayerVisibility( kUCIPage, "I01-CallActive", true , "fade" )
    print("funcCallActivePopup set")
  else
    Uci.SetLayerVisibility( kUCIPage, "I01-CallActive", false , "none" )
  end --if
end--func

function funcShowPresetSavedSublayer()
  if Controls.pinLEDPresetSaved.Boolean then 
    Uci.SetLayerVisibility( kUCIPage, "J04-CamPresetSaved", true , "fade" )
    print("funcPresetSavedPopup set")
  else
    Uci.SetLayerVisibility( kUCIPage, "J04-CamPresetSaved", false , "none" )
  end --if
end--func

function funcShowHDMISublayer()
  if Controls.pinLEDHDMIConnected.Boolean then 
    Uci.SetLayerVisibility( kUCIPage, "L05-Laptop", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "L01-HDMIDisconnected", false , "none" )
  else
    Uci.SetLayerVisibility( kUCIPage, "L01-HDMIDisconnected", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "L05-Laptop", false , "none" )
  end --if
end--func

function funcShowACPRSublayer()
  if Controls.pinLEDACPRActive.Boolean then 
    Uci.SetLayerVisibility( kUCIPage, "J02-ACPROn", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "J05-CameraControls", false , "none" )
  else
    Uci.SetLayerVisibility( kUCIPage, "J05-CameraControls", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "J02-ACPROn", false , "none" )
    print("funcShowACPRSublayer set")
  end --if
end--func

function funcShowCameraSublayer()
  if Controls.pinLEDUSBPC.Boolean then 
    Uci.SetLayerVisibility( kUCIPage, "J05-CameraControls", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "J01-USBConnectedNOT", false , "none" )
    print("funcShowCameraSublayer set")
  else
    Uci.SetLayerVisibility( kUCIPage, "J01-USBConnectedNOT", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "J05-CameraControls", false , "none" )
  end --if
end--func
-----------------------------------------------------------------------------------------------------------------
--turn off ALL layers --turn on the layer of varActiveLayer
function  funcShowLayer()
  Uci.SetLayerVisibility( kUCIPage, "A01-Initialize", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "B01-IncomingCall", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "C01-Start", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "D01-ShutdownConfirm", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "E01-SystemProgressWarming", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "E02-SystemProgressCooling", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "E05-SystemProgress", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "H01-RoomControls", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "I01-CallActive", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "I02-HelpPC", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "I03-HelpLaptop", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "I04-HelpWireless", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "I05-HelpRouting", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "J01-USBConnectedNOT", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "J02-ACPROn", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "J04-CamPresetSaved", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "J05-CameraControls", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "P05-PC", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "L01-HDMIDisconnected", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "L05-Laptop", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "W05-Wireless", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R01-Routing-Lobby", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R02-Routing-WTerrace", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R03-Routing-NTerraceWall", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R04-Routing-Garden", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R05-Routing-NTerraceFloor", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "R10-Routing", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "V05-Dialer", false , "none" )
  Uci.SetLayerVisibility( kUCIPage, "X01-ProgramVolume", true , "none" )
  Uci.SetLayerVisibility( kUCIPage, "Y01-Navbar", true , "none" )
  Uci.SetLayerVisibility( kUCIPage, "Z01-Base", true , "none" )
  print("funcShowLayer set")

  if varActiveLayer == kLayer_Initialize then
    Uci.SetLayerVisibility( kUCIPage, "A01-Initialize", true , "fade" )
    funcHideBaseLayers()
  elseif varActiveLayer == kLayer_IncomingCall then 
    Uci.SetLayerVisibility( kUCIPage, "B01-IncomingCall", true , "fade" )
  elseif varActiveLayer == kLayer_Start then 
    Uci.SetLayerVisibility( kUCIPage, "C01-Start", true , "fade" )
    funcHideBaseLayers()
  elseif varActiveLayer == kLayer_Warming then 
    Uci.SetLayerVisibility( kUCIPage, "E05-SystemProgress", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "E01-SystemProgressWarming", true , "fade" )
    funcHideBaseLayers()
  elseif varActiveLayer == kLayer_Cooling then 
    Uci.SetLayerVisibility( kUCIPage, "E05-SystemProgress", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "E02-SystemProgressCooling", true , "fade" )
    funcHideBaseLayers()
  elseif varActiveLayer == kLayer_RoomControls then 
    Uci.SetLayerVisibility( kUCIPage, "H01-RoomControls", true , "fade" )
    Uci.SetLayerVisibility( kUCIPage, "X01-ProgramVolume", false  , "none" )
  elseif varActiveLayer == kLayer_PC then 
    Uci.SetLayerVisibility( kUCIPage, "P05-PC", true , "fade" )
    funcCallActivePopup()
    funcShowCameraSublayer()
    funcShowPresetSavedSublayer()
    funcShowACPRSublayer()
  elseif varActiveLayer == kLayer_Laptop then 
    Uci.SetLayerVisibility( kUCIPage, "L05-Laptop", true , "fade" )
    funcCallActivePopup()
    funcShowHDMISublayer()
    funcShowCameraSublayer()
    funcShowPresetSavedSublayer()
    funcShowACPRSublayer()
  elseif varActiveLayer == kLayer_Wireless then 
    Uci.SetLayerVisibility( kUCIPage, "W05-Wireless", true , "fade" )
  elseif varActiveLayer == kLayer_Routing then
    Uci.SetLayerVisibility( kUCIPage, "R10-Routing", true , "fade" )
  elseif varActiveLayer == kLayer_Dialer then
    Uci.SetLayerVisibility( kUCIPage, "V05-Dialer", true , "fade" )
    funcCallActivePopup()
  end --if
end--func

-----------------------------------------------------------------------------------------------------------------
function funcInterlock()
  -- --set ALL Navbar layers and buttons false, then set layer Visbiliity of the button with Boolean that is true
  for i = 1, 11 do
    Controls["btnNav" .. string.format("%02d", i)].Boolean = false
  end--for
  print("funcInterlock set")
  -- Mapping layers to button indices
  local layerToButton = {
    [kLayer_Initialize]   = 1,
    [kLayer_IncomingCall] = 2,
    [kLayer_Start]        = 3,
    [kLayer_Warming]      = 4,
    [kLayer_Cooling]      = 5,
    [kLayer_RoomControls] = 6,
    [kLayer_PC]           = 7,
    [kLayer_Laptop]       = 8,
    [kLayer_Wireless]     = 9,
    [kLayer_Routing]      = 10,
    [kLayer_Dialer]       = 11,
  }
  -- Set the correct button to true based on the active layer
  local btnIndex = layerToButton[varActiveLayer]
  if btnIndex then
    Controls["btnNav" .. string.format("%02d", btnIndex)].Boolean = true
  end--if
end--func


function funcDebug()
  local layers = {
    {var = kLayer_Initialize,   msg = "Set UCI to Initialize"},
    {var = kLayer_IncomingCall, msg = "Set UCI to IncomingCall"},
    {var = kLayer_Start,        msg = "Set UCI to Start"},
    {var = kLayer_Warming,      msg = "Set UCI to Warming"},
    {var = kLayer_Cooling,      msg = "Set UCI to Cooling"},
    {var = kLayer_RoomControls, msg = "Set UCI to Room Controls"},
    {var = kLayer_PC,           msg = "Set UCI to PC"},
    {var = kLayer_Laptop,       msg = "Set UCI to Laptop"},
    {var = kLayer_Wireless,     msg = "Set UCI to Wireless"},
    {var = kLayer_Routing,      msg = "Set UCI to Routing"},
    {var = kLayer_Dialer,       msg = "Set UCI to Dialer"},
  }

  for i = 1, #layers do
    if varActiveLayer == layers[i].var then
      print(layers[i].msg)
      break
    end--if
  end--for
end--func

-----------------------------------------------------------------------------------------------------------------
-- Eventhandlers 
-----------------------------------------------------------------------------------------------------------------
---- Nav Buttons 
-----------------------------------------------------------------------------------------------------------------
arrbtnNavs = {
  Controls.btnNav01,
  Controls.btnNav02,
  Controls.btnNav03,
  Controls.btnNav04,
  Controls.btnNav05,
  Controls.btnNav06,
  Controls.btnNav07,
  Controls.btnNav08,
  Controls.btnNav09,
  Controls.btnNav10,
  Controls.btnNav11,
}

function funcbtnNavEventHandler(argIndex)
  varActiveLayer = argIndex
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--func

for i,ctl in ipairs(arrbtnNavs) do
  ctl.EventHandler = function ()
    funcbtnNavEventHandler(i)
  end--EH
end--for
-----------------------------------------------------------------------------------------------------------------
---- System State buttons
-----------------------------------------------------------------------------------------------------------------
function funcSetPGMState(ctl)
  if ctl.Boolean or Controls.mtrPGMVolLvl.Position == 0 then
    Controls.mtrPGMVolLvl.Color = "#CCCCCC"
    Controls.btnPGMVolMute.CssClass = "icon-volume_off"
  else
    Controls.mtrPGMVolLvl.Color = "#0561A5"
    Controls.btnPGMVolMute.CssClass = "icon-volume_mute"
  end--if
end--func

funcSetPGMState(Controls.btnPGMVolMute)

Controls.btnPGMVolMute.EventHandler = funcSetPGMState
-----------------------------------------------------------------------------------------------------------------
---- knbProgressBar animation
-----------------------------------------------------------------------------------------------------------------
-- Global timer to prevent overlap
-- Global timer and completion state
local loadingTimer = nil
local isAnimating = false  -- Prevents overlapping animations

function funcStartLoadingBar(isPoweringOn)
    if isAnimating then return end  -- Block overlapping calls
    isAnimating = true

    local duration
    if isPoweringOn then
        duration = tonumber(Uci.Variables["timeProgressWarming"]) or 7
        assert(type(duration) == "number", "timeProgressWarming must be a number")
    else
        duration = tonumber(Uci.Variables["timeProgressCooling"]) or 7
        assert(type(duration) == "number", "timeProgressCooling must be a number")
    end--if

    local steps = 100
    local interval = duration / steps
    local currentStep = 0

    -- Stop/reset previous timer
    if loadingTimer then
        loadingTimer:Stop()
        loadingTimer = nil
    end--if
    loadingTimer = Timer.New()

    -- Initial setup
    Controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    Controls.txtProgressBar.String = isPoweringOn and "0%" or "100%"

    loadingTimer.EventHandler = function()
        currentStep = currentStep + 1

        -- Update progress bar and text
        if isPoweringOn then
            Controls.knbProgressBar.Value = currentStep
            Controls.txtProgressBar.String = currentStep .. "%"
        else
            Controls.knbProgressBar.Value = 100 - currentStep
            Controls.txtProgressBar.String = (100 - currentStep) .. "%"
        end--if

        -- Check for completion
        if currentStep >= steps then
            loadingTimer:Stop()  -- Critical: Stop the timer
            isAnimating = false  -- Reset animation lock

            -- Fire the layer switch ONCE
            if isPoweringOn then
                funcbtnNavEventHandler(kLayer_PC)
            else
                funcbtnNavEventHandler(kLayer_Start)
            end--if
        else
            loadingTimer:Start(interval)
        end--if
    end--EH

    loadingTimer:Start(interval)
end--func

-----------------------------------------------------------------------------------------------------------------
-- Start the system
Controls.btnStartSystem.EventHandler = function () --varActiveLayer = kLayer_Warming
  funcStartLoadingBar(true)
  funcbtnNavEventHandler(kLayer_Warming)
  print("System started with Start button")
end--EH
-- Show Shutdown Confirm page
Controls.btnNavShutdown.EventHandler = function () --varActiveLayer = kLayer_ShutdownConfirm
  Uci.SetLayerVisibility( kUCIPage, "D01-ShutdownConfirm", true , "fade" )
  print("Shutdown Confrim page set")
end--EH
-- Cancel Shut down of the system
Controls.btnShutdownCancel.EventHandler = function () --varActiveLayer = kLayer_Cooling
  Uci.SetLayerVisibility( kUCIPage, "D01-ShutdownConfirm", false , "fade" )
  print("Shutdown cancelled by Cancel button")
  funcDebug()
end--EH
-- Shut down the system
Controls.btnShutdownConfirm.EventHandler = function ()
  funcStartLoadingBar(false)
  funcbtnNavEventHandler(kLayer_Cooling)
end--EH
-----------------------------------------------------------------------------------------------------------------
---- External Triggers 
-----------------------------------------------------------------------------------------------------------------
-- USB is Connected - PC
Controls.pinLEDUSBPC.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_PC
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH
-- USB is Connected - Laptop
Controls.pinLEDUSBLaptop.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH
-- USB Off Hook - PC
Controls.pinLEDOffHookPC.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_PC
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH
-- USB Off Hook - Laptop
Controls.pinLEDOffHookLaptop.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH
-- HDMI connected - Laptop
Controls.pinLEDLaptop01Active.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop01])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop01])
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH

Controls.pinLEDLaptop02Active.EventHandler = function (ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop02])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop02])
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebug()
end--EH
-----------------------------------------------------------------------------------------------------------------
---- Nav button and text label legends
-----------------------------------------------------------------------------------------------------------------

arrUCILegends = {
 Controls.txtNav01,
 Controls.txtNav02,
 Controls.txtNav03, 
 Controls.txtNav04,
 Controls.txtNav05,
 Controls.txtNav06,
 Controls.txtNav07,
 Controls.txtNav08,
 Controls.txtNav09,
 Controls.txtNav10,
 Controls.txtNav11,
 Controls.txtNavShutdown,
 Controls.txtRoomName,
 Controls.txtRoomNameStart,
}

arrUCIUserLabels = {
   Uci.Variables.txtLabelNav01,
   Uci.Variables.txtLabelNav02,
   Uci.Variables.txtLabelNav03,
   Uci.Variables.txtLabelNav04,
   Uci.Variables.txtLabelNav05,
   Uci.Variables.txtLabelNav06,
   Uci.Variables.txtLabelNav07,
   Uci.Variables.txtLabelNav08,
   Uci.Variables.txtLabelNav09,
   Uci.Variables.txtLabelNav10,
   Uci.Variables.txtLabelNav11,
   Uci.Variables.txtLabelNavShutdown,
   Uci.Variables.txtLabelRoomName,
   Uci.Variables.txtLabelRoomName,
}

function funcUpdateLegends()
  for i,lbl in ipairs(arrUCILegends) do
    lbl.Legend = arrUCIUserLabels[i].String
  end--EH
end--func

for i,lbl in ipairs(arrUCIUserLabels) do
  lbl.EventHandler = function ()
    funcUpdateLegends()
  end--EH
  print("funcUpdateLegends() ran succesfully")
end--for

-------------------------------------------------------------------------------------------------------------------------------------

function funcInit()
  varActiveLayer = kLayer_Start
  funcShowLayer()
  funcInterlock()
  funcDebug()
  funcUpdateLegends()
  funcSetcodenameNV32()
  funcSetcodenameCamPresetCtrl()
  funcStartLoadingBar(false)
  funcSetTimeProgress()
  print("UCI Initialized")
end--func

--in the Mainline of the script and will run once at Startup

funcInit()