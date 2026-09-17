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
kLayer_Initialize   = 1
kLayer_IncomingCall = 2
kLayer_Start        = 3
kLayer_Warming      = 4
kLayer_Cooling      = 5
kLayer_RoomControls = 6
kLayer_PC           = 7
kLayer_Laptop       = 8
kLayer_Wireless     = 9
kLayer_Routing      = 10
kLayer_Dialer       = 11

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

function funcShowRoutingSublayer()
  if Controls..Boolean then 
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
function funcShowLayer()
    -- Hide all layers
    local layersToHide = {
        "A01-Initialize", 
        "B01-IncomingCall", 
        "C01-Start", 
        "D01-ShutdownConfirm",
        "E01-SystemProgressWarming", 
        "E02-SystemProgressCooling", 
        "E05-SystemProgress",
        "H01-RoomControls", 
        "I01-CallActive", 
        "I02-HelpPC", 
        "I03-HelpLaptop",
        "I04-HelpWireless", 
        "I05-HelpRouting", 
        "J01-USBConnectedNOT", 
        "J02-ACPROn",
        "J04-CamPresetSaved", 
        "J05-CameraControls", 
        "P05-PC", 
        "L01-HDMIDisconnected",
        "L05-Laptop", 
        "W05-Wireless", 
        "R01-Routing-Lobby", 
        "R02-Routing-WTerrace",
        "R03-Routing-NTerraceWall", 
        "R04-Routing-Garden", 
        "R05-Routing-NTerraceFloor",
        "R10-Routing", 
        "V05-Dialer", 
        "X01-ProgramVolume", 
        "Y01-Navbar", 
        "Z01-Base"
    }
    
    for i, layer in ipairs(layersToHide) do
        Uci.SetLayerVisibility(kUCIPage, layer, false, "none")
    end--for

    -- Set base layers visible
    Uci.SetLayerVisibility(kUCIPage, "X01-ProgramVolume", true, "none")
    Uci.SetLayerVisibility(kUCIPage, "Y01-Navbar", true, "none")
    Uci.SetLayerVisibility(kUCIPage, "Z01-Base", true, "none")

    -- Layer configuration table
    local layerConfigs = {
        [kLayer_Initialize] = {showLayers = {"A01-Initialize"},
            callFunctions = {funcHideBaseLayers}
        },
        [kLayer_IncomingCall] = {showLayers = {"B01-IncomingCall"}},
        [kLayer_Start] = {showLayers = {"C01-Start"},
            callFunctions = {funcHideBaseLayers}
        },
        [kLayer_Warming] = {showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
            callFunctions = {funcHideBaseLayers}
        },
        [kLayer_Cooling] = {showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
            callFunctions = {funcHideBaseLayers}
        },
        [kLayer_RoomControls] = {showLayers = {"H01-RoomControls"},
            hideLayers = {"X01-ProgramVolume"}
        },
        [kLayer_PC] = {showLayers = {"P05-PC"},
            callFunctions = {funcCallActivePopup, 
            funcShowCameraSublayer, 
            funcShowPresetSavedSublayer, 
            funcShowACPRSublayer}
        },
        [kLayer_Laptop] = {showLayers = {"L05-Laptop"},
            callFunctions = {funcCallActivePopup, 
            funcShowHDMISublayer,
            funcShowCameraSublayer, 
            funcShowPresetSavedSublayer, 
            uncShowACPRSublayer}
        },
        [kLayer_Wireless] = {showLayers = {"W05-Wireless"}},
        [kLayer_Routing] = {showLayers = {"R10-Routing"},
        },
        [kLayer_Dialer] = {showLayers = {"V05-Dialer"},
            callFunctions = {funcCallActivePopup}
        }
    }

    -- Apply active layer configuration
    local config = layerConfigs[varActiveLayer]
    if config then
        for i, layer in ipairs(config.showLayers or {}) do
            Uci.SetLayerVisibility(kUCIPage, layer, true, "fade")
        end--for
        for i, layer in ipairs(config.hideLayers or {}) do
            Uci.SetLayerVisibility(kUCIPage, layer, false, "none")
        end--for
        for i, func in ipairs(config.callFunctions or {}) do
            func()
        end--for
    end--if

    print("funcShowLayer set for " .. kUCIPage)
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
  print("System started with Start buttonfor " .. kUCIPage)
end--EH
-- Show Shutdown Confirm page
Controls.btnNavShutdown.EventHandler = function () --varActiveLayer = kLayer_ShutdownConfirm
  Uci.SetLayerVisibility( kUCIPage, "D01-ShutdownConfirm", true , "fade" )
  print("Shutdown Confrim page setfor " .. kUCIPage)
end--EH
-- Cancel Shut down of the system
Controls.btnShutdownCancel.EventHandler = function () --varActiveLayer = kLayer_Cooling
  Uci.SetLayerVisibility( kUCIPage, "D01-ShutdownConfirm", false , "fade" )
  print("Shutdown cancelled by Cancel buttonfor " .. kUCIPage)
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
  print("funcUpdateLegends() ran succesfully for " .. kUCIPage)
end--for

-------------------------------------------------------------------------------------------------------------------------------------

function funcInit()
  varActiveLayer = kLayer_Start
  funcShowLayer()
  funcInterlock()
  funcDebug()
  funcUpdateLegends()
--   funcSetcodenameNV32()
--   funcSetcodenameCamPresetCtrl()
--   funcStartLoadingBar(false)
--   funcSetTimeProgress()
  print("UCI Initialized for " .. kUCIPage)
end--func

--in the Mainline of the script and will run once at Startup

funcInit()