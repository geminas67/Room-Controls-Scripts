-----------------------------------------------------------------------------------------------------------------
-- Named Components
-----------------------------------------------------------------------------------------------------------------
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
-- UCI Page Name will be passed as parameter
-- ** change UCI Page Name in funcInit() at the END of the script ** --

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
function funcSetTimeProgress()
  timeProgWarming = Uci.Variables["timeProgressWarming"] or "10"
  timeProgCooling = Uci.Variables["timeProgressCooling"] or "5"
end

function funcHideBaseLayers(uciPage)
  Uci.SetLayerVisibility(uciPage, "X01-ProgramVolume", false, "none")
  Uci.SetLayerVisibility(uciPage, "Y01-Navbar", false, "none")
  Uci.SetLayerVisibility(uciPage, "Z01-Base", false, "none")
  print("funcHideBaseLayers set")
end

function funcCallActivePopup(uciPage)
  if Controls.pinCallActive.Boolean then 
    Uci.SetLayerVisibility(uciPage, "I01-CallActive", true, "fade")
    print("funcCallActivePopup set")
  else
    Uci.SetLayerVisibility(uciPage, "I01-CallActive", false, "none")
  end
end

function funcShowPresetSavedSublayer(uciPage)
  if Controls.pinLEDPresetSaved.Boolean then 
    Uci.SetLayerVisibility(uciPage, "J04-CamPresetSaved", true, "fade")
    print("funcPresetSavedPopup set")
  else
    Uci.SetLayerVisibility(uciPage, "J04-CamPresetSaved", false, "none")
  end
end

function funcShowHDMISublayer(uciPage)
  if Controls.pinLEDHDMIConnected.Boolean then 
    Uci.SetLayerVisibility(uciPage, "L05-Laptop", true, "fade")
    Uci.SetLayerVisibility(uciPage, "L01-HDMIDisconnected", false, "none")
  else
    Uci.SetLayerVisibility(uciPage, "L01-HDMIDisconnected", true, "fade")
    Uci.SetLayerVisibility(uciPage, "L05-Laptop", false, "none")
  end
end

function funcShowACPRSublayer(uciPage)
  if Controls.pinLEDACPRActive.Boolean then 
    Uci.SetLayerVisibility(uciPage, "J02-ACPROn", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", false, "none")
  else
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J02-ACPROn", false, "none")
    print("funcShowACPRSublayer set")
  end
end

function funcShowCameraSublayer(uciPage)
  if Controls.pinLEDUSBPC.Boolean then 
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J01-USBConnectedNOT", false, "none")
    print("funcShowCameraSublayer set")
  else
    Uci.SetLayerVisibility(uciPage, "J01-USBConnectedNOT", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", false, "none")
  end
end

function funcShowRoutingSublayer(uciPage)
  -- This function needs a valid Controls property to check. Placeholder logic:
  if Controls.pinSomeRoutingControl and Controls.pinSomeRoutingControl.Boolean then 
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J01-USBConnectedNOT", false, "none")
    print("funcShowCameraSublayer set")
  else
    Uci.SetLayerVisibility(uciPage, "J01-USBConnectedNOT", true, "fade")
    Uci.SetLayerVisibility(uciPage, "J05-CameraControls", false, "none")
  end
end

function funcShowLayer(uciPage)
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
  for _, layer in ipairs(layersToHide) do
    Uci.SetLayerVisibility(uciPage, layer, false, "none")
  end

  -- Set base layers visible
  Uci.SetLayerVisibility(uciPage, "X01-ProgramVolume", true, "none")
  Uci.SetLayerVisibility(uciPage, "Y01-Navbar", true, "none")
  Uci.SetLayerVisibility(uciPage, "Z01-Base", true, "none")

  -- Layer configuration table
  local layerConfigs = {
    [kLayer_Initialize] = {
      showLayers = {"A01-Initialize"},
      callFunctions = {function() funcHideBaseLayers(uciPage) end}
    },
    [kLayer_IncomingCall] = {showLayers = {"B01-IncomingCall"}},
    [kLayer_Start] = {
      showLayers = {"C01-Start"},
      callFunctions = {function() funcHideBaseLayers(uciPage) end}
    },
    [kLayer_Warming] = {
      showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
      callFunctions = {function() funcHideBaseLayers(uciPage) end}
    },
    [kLayer_Cooling] = {
      showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
      callFunctions = {function() funcHideBaseLayers(uciPage) end}
    },
    [kLayer_RoomControls] = {
      showLayers = {"H01-RoomControls"},
      hideLayers = {"X01-ProgramVolume"}
    },
    [kLayer_PC] = {
      showLayers = {"P05-PC"},
      callFunctions = {
        function() funcCallActivePopup(uciPage) end,
        function() funcShowCameraSublayer(uciPage) end,
        function() funcShowPresetSavedSublayer(uciPage) end,
        function() funcShowACPRSublayer(uciPage) end
      }
    },
    [kLayer_Laptop] = {
      showLayers = {"L05-Laptop"},
      callFunctions = {
        function() funcCallActivePopup(uciPage) end,
        function() funcShowHDMISublayer(uciPage) end,
        function() funcShowCameraSublayer(uciPage) end,
        function() funcShowPresetSavedSublayer(uciPage) end,
        function() funcShowACPRSublayer(uciPage) end
      }
    },
    [kLayer_Wireless] = {showLayers = {"W05-Wireless"}},
    [kLayer_Routing] = {showLayers = {"R10-Routing"}},
    [kLayer_Dialer] = {
      showLayers = {"V05-Dialer"},
      callFunctions = {function() funcCallActivePopup(uciPage) end}
    }
  }

  -- Apply active layer configuration
  local config = layerConfigs[varActiveLayer]
  if config then
    for _, layer in ipairs(config.showLayers or {}) do
      Uci.SetLayerVisibility(uciPage, layer, true, "fade")
    end
    for _, layer in ipairs(config.hideLayers or {}) do
      Uci.SetLayerVisibility(uciPage, layer, false, "none")
    end
    for _, func in ipairs(config.callFunctions or {}) do
      func()
    end
  end

  print("funcShowLayer set for " .. uciPage)
end

function funcInterlock()
  for i = 1, 11 do
    Controls["btnNav" .. string.format("%02d", i)].Boolean = false
  end
  print("funcInterlock set")
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
  local btnIndex = layerToButton[varActiveLayer]
  if btnIndex then
    Controls["btnNav" .. string.format("%02d", btnIndex)].Boolean = true
  end
end

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
    end
  end
end

-----------------------------------------------------------------------------------------------------------------
-- Eventhandlers 
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

function funcbtnNavEventHandler(argIndex, uciPage)
  varActiveLayer = argIndex
  funcShowLayer(uciPage)
  funcInterlock()
  funcDebug()
end

-- We'll store the current page for use in event handlers
local currentUCIPage = nil

for i,ctl in ipairs(arrbtnNavs) do
  ctl.EventHandler = function()
    funcbtnNavEventHandler(i, currentUCIPage)
  end
end

-----------------------------------------------------------------------------------------------------------------
function funcSetPGMState(ctl)
  if ctl.Boolean or Controls.mtrPGMVolLvl.Position == 0 then
    Controls.mtrPGMVolLvl.Color = "#CCCCCC"
    Controls.btnPGMVolMute.CssClass = "icon-volume_off"
  else
    Controls.mtrPGMVolLvl.Color = "#0561A5"
    Controls.btnPGMVolMute.CssClass = "icon-volume_mute"
  end
end

funcSetPGMState(Controls.btnPGMVolMute)
Controls.btnPGMVolMute.EventHandler = funcSetPGMState

-----------------------------------------------------------------------------------------------------------------
-- knbProgressBar animation
-----------------------------------------------------------------------------------------------------------------
local loadingTimer = nil
local isAnimating = false

function funcStartLoadingBar(isPoweringOn, uciPage)
  if isAnimating then return end
  isAnimating = true

  local duration
  if isPoweringOn then
    duration = tonumber(Uci.Variables["timeProgressWarming"]) or 7
    assert(type(duration) == "number", "timeProgressWarming must be a number")
  else
    duration = tonumber(Uci.Variables["timeProgressCooling"]) or 7
    assert(type(duration) == "number", "timeProgressCooling must be a number")
  end

  local steps = 100
  local interval = duration / steps
  local currentStep = 0

  if loadingTimer then
    loadingTimer:Stop()
    loadingTimer = nil
  end
  loadingTimer = Timer.New()

  Controls.knbProgressBar.Value = isPoweringOn and 0 or 100
  Controls.txtProgressBar.String = isPoweringOn and "0%" or "100%"

  loadingTimer.EventHandler = function()
    currentStep = currentStep + 1

    if isPoweringOn then
      Controls.knbProgressBar.Value = currentStep
      Controls.txtProgressBar.String = currentStep .. "%"
    else
      Controls.knbProgressBar.Value = 100 - currentStep
      Controls.txtProgressBar.String = (100 - currentStep) .. "%"
    end

    if currentStep >= steps then
      loadingTimer:Stop()
      isAnimating = false
      if isPoweringOn then
        funcbtnNavEventHandler(kLayer_PC, uciPage)
      else
        funcbtnNavEventHandler(kLayer_Start, uciPage)
      end
    else
      loadingTimer:Start(interval)
    end
  end

  loadingTimer:Start(interval)
end

-----------------------------------------------------------------------------------------------------------------
-- Start the system
Controls.btnStartSystem.EventHandler = function()
  funcStartLoadingBar(true, currentUCIPage)
  funcbtnNavEventHandler(kLayer_Warming, currentUCIPage)
  print("System started with Start button for " .. currentUCIPage)
end

Controls.btnNavShutdown.EventHandler = function()
  Uci.SetLayerVisibility(currentUCIPage, "D01-ShutdownConfirm", true, "fade")
  print("Shutdown Confirm page set for " .. currentUCIPage)
end

Controls.btnShutdownCancel.EventHandler = function()
  Uci.SetLayerVisibility(currentUCIPage, "D01-ShutdownConfirm", false, "fade")
  print("Shutdown cancelled by Cancel button for " .. currentUCIPage)
  funcDebug()
end

Controls.btnShutdownConfirm.EventHandler = function()
  funcStartLoadingBar(false, currentUCIPage)
  funcbtnNavEventHandler(kLayer_Cooling, currentUCIPage)
end

-----------------------------------------------------------------------------------------------------------------
-- External Triggers 
-----------------------------------------------------------------------------------------------------------------
Controls.pinLEDUSBPC.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_PC
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

Controls.pinLEDUSBLaptop.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

Controls.pinLEDOffHookPC.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_PC
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

Controls.pinLEDOffHookLaptop.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

Controls.pinLEDLaptop01Active.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop01])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop01])
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

Controls.pinLEDLaptop02Active.EventHandler = function(ctl)
  if ctl.Boolean then
    varActiveLayer = kLayer_Laptop
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop02])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop02])
  end
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
end

-----------------------------------------------------------------------------------------------------------------
-- Nav button and text label legends
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
  end
end

for i,lbl in ipairs(arrUCIUserLabels) do
  lbl.EventHandler = function()
    funcUpdateLegends()
  end
  print("funcUpdateLegends() ran successfully")
end

-----------------------------------------------------------------------------------------------------------------
function funcInit(pageName)
  currentUCIPage = pageName
  varActiveLayer = kLayer_Start
  funcShowLayer(currentUCIPage)
  funcInterlock()
  funcDebug()
  funcUpdateLegends()
  funcSetcodenameNV32()
  funcSetcodenameCamPresetCtrl()
  funcStartLoadingBar(false, currentUCIPage)
  funcSetTimeProgress()
  print("UCI Initialized for " .. currentUCIPage)
end

-- Run initialization with your page name
funcInit("UCI MPR(005)")
