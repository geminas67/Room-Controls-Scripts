-------------------[ Controls ]-------------------
local controls = {
  btnNavRoom = Controls.btnNavRoom,
  btnNavDisplays = Controls.btnNavDisplays,
  btnNavCameras = Controls.btnNavCameras,
  pinLEDUSB = Controls.pinLEDUSB,
  listOut01 = Controls.listOut01,
  listOut02 = Controls.listOut02,
  pinLEDLaptop01Active = Controls.pinLEDLaptop01Active,
  pinLEDLaptop02Active = Controls.pinLEDLaptop02Active,
  -- UCI Variables
  navBtnRoomLegend = Uci.Variables.navBtnRoomLegend,
  navBtnDisplaysLegend = Uci.Variables.navBtnDisplaysLegend,
  navBtnCamerasLegend = Uci.Variables.navBtnCamerasLegend,
  varNV32CodeName = Uci.Variables.varNV32CodeName,
  friendlyHDMI01 = Uci.Variables.friendlyHDMI01,
  friendlyHDMI02 = Uci.Variables.friendlyHDMI02,
  friendlyHDMI03 = Uci.Variables.friendlyHDMI03,
  friendlyGraphic01 = Uci.Variables.friendlyGraphic01,
  friendlyGraphic02 = Uci.Variables.friendlyGraphic02,
  friendlyGraphic03 = Uci.Variables.friendlyGraphic03,
}

-- Constants --
kLayer_Room = 1
kLayer_Displays = 2
kLayer_Cameras = 3
varActiveLayer = kLayer_Room

-- Functions --
function funcUpdateLegends()
  controls.btnNavRoom.Legend = Uci.Variables.navBtnRoomLegend.String
  controls.btnNavDisplays.Legend = Uci.Variables.navBtnDisplaysLegend.String
  controls.btnNavCameras.Legend = Uci.Variables.navBtnCamerasLegend.String
end

function funcShowCameraSublayer()
  if controls.pinLEDUSB.Boolean then 
  Uci.SetLayerVisibility( "classUCI", "C2_USB_Connected", true , "fade" )
  Uci.SetLayerVisibility( "classUCI", "C3_USB_Connected_NOT", false , "none" )
  else
  Uci.SetLayerVisibility( "classUCI", "C2_USB_Connected", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "C3_USB_Connected_NOT", true , "fade" )
  end --if
end
--turn off ALL layers --turn on the layer of varActiveLayer
function  funcShowLayer()
  Uci.SetLayerVisibility( "classUCI", "A1_Room", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "B1_Displays", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "C1_Cameras", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "C2_USB_Connected", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "C3_USB_Connected_NOT", false , "none" )
  Uci.SetLayerVisibility( "classUCI", "Y1_Base Controls", true , "fade" )
  Uci.SetLayerVisibility( "classUCI", "Z1_BG", true , "fade" )

  if varActiveLayer == kLayer_Room then
    Uci.SetLayerVisibility( "classUCI", "A1_Room", true , "fade" )
  elseif varActiveLayer == kLayer_Displays then 
    Uci.SetLayerVisibility( "classUCI", "B1_Displays", true , "fade" )
  elseif varActiveLayer == kLayer_Cameras then
    Uci.SetLayerVisibility( "classUCI", "C1_Cameras", true , "fade" )
    funcShowCameraSublayer()
  end --if
end

function funcInterlock() --set ALL layers and buttons falsse, then set layer Visbiliity of the button with Boolean that is true
  controls.btnNavRoom.Boolean = false 
  controls.btnNavDisplays.Boolean = false 
  controls.btnNavCameras.Boolean = false

  if varActiveLayer == kLayer_Room then
    controls.btnNavRoom.Boolean = true 
  elseif varActiveLayer == kLayer_Displays then 
    controls.btnNavDisplays.Boolean = true 
  elseif varActiveLayer == kLayer_Cameras then
    controls.btnNavCameras.Boolean = true
  end--if
end 
--print varActiveLayer to Debugger
function funcDebugger()
  if varActiveLayer == kLayer_Room then
    print("Set UCI to Room") 
  elseif varActiveLayer == kLayer_Displays then 
    print("Set UCI to Displays") 
  elseif varActiveLayer == kLayer_Cameras then
    print("Set UCI to Cameras") 
  end--if
end 

--btnNavRoom is Active
controls.btnNavRoom.EventHandler = function ()
  varActiveLayer = kLayer_Room
  funcShowLayer()
  funcInterlock()
  funcDebugger()
end
--btnNavDisplays is Active
controls.btnNavDisplays.EventHandler = function ()
  varActiveLayer = kLayer_Displays
  funcShowLayer()
  funcInterlock()
  funcDebugger()
end
--btnNavCameras is Active
controls.btnNavCameras.EventHandler = function ()
  varActiveLayer = kLayer_Cameras
  funcShowLayer()
  funcInterlock()
  funcDebugger()
end
--btnNavCameras is Active
controls.pinLEDUSB.EventHandler = function (ctl)
  if ctl.Boolean then
  varActiveLayer = kLayer_Cameras
  end--if
  funcShowLayer()
  funcInterlock()
  funcDebugger()
end

-------------------------------------------------------------------------------------------------------------------------------------

Uci.Variables.navBtnRoomLegend.EventHandler = function ()
  funcUpdateLegends()
end

Uci.Variables.navBtnDisplaysLegend.EventHandler = function ()
  funcUpdateLegends()
end

Uci.Variables.navBtnCamerasLegend.EventHandler = function ()
  funcUpdateLegends()
end
-------------------------------------------------------------------------------------------------------------------------------------

function funcSetNV32CodeName()
  devNV32 = Component.New(Uci.Variables.varNV32CodeName.String)
end
Uci.Variables.varNV32CodeName.EventHandler = funcSetNV32CodeName

arrListBox = {
  controls.listOut01,
  controls.listOut02,
}

function funcSetChoices()
  arrFriendlyNames = {
    --assign name of list box
    Uci.Variables.friendlyHDMI01.String,
    Uci.Variables.friendlyHDMI02.String,
    Uci.Variables.friendlyHDMI03.String,
    Uci.Variables.friendlyGraphic01.String,
  }
  tblBabelFish = {}
  tblBabelFish[Uci.Variables.friendlyHDMI01.String] = "HDMI 1"
  tblBabelFish[Uci.Variables.friendlyHDMI02.String] = "HDMI 2"
  tblBabelFish[Uci.Variables.friendlyHDMI03.String] = "HDMI 3"
  tblBabelFish[Uci.Variables.friendlyGraphic01.String] = "Graphic 1"
  tblBabelFish[Uci.Variables.friendlyGraphic02.String] = "Graphic 2"
  tblBabelFish[Uci.Variables.friendlyGraphic03.String] = "Graphic 3"

  tblBabelFish["HDMI 1"] = Uci.Variables.friendlyHDMI01.String
  tblBabelFish["HDMI 2"] = Uci.Variables.friendlyHDMI02.String
  tblBabelFish["HDMI 3"] = Uci.Variables.friendlyHDMI03.String
  tblBabelFish["Graphic 1"] = Uci.Variables.friendlyGraphic01.String
  tblBabelFish["Graphic 2"] = Uci.Variables.friendlyGraphic02.String
  tblBabelFish["Graphic 3"] = Uci.Variables.friendlyGraphic03.String

  --loop to assign .Choices
  for i, ctl in ipairs(arrListBox) do
    ctl.Choices = arrFriendlyNames
  end--for
end

--list EventHandlers
Uci.Variables.friendlyHDMI01.EventHandler = funcSetChoices
Uci.Variables.friendlyHDMI02.EventHandler = funcSetChoices
Uci.Variables.friendlyHDMI03.EventHandler = funcSetChoices
Uci.Variables.friendlyGraphic01.EventHandler = funcSetChoices
Uci.Variables.friendlyGraphic02.EventHandler = funcSetChoices
Uci.Variables.friendlyGraphic03.EventHandler = funcSetChoices

function funcVideoDebugger(argWho,argInput,argWhy)
  print(string.format("%s routed %s/%s because : %s", argWho, argInput, tblBabelFish[argInput], argWhy))
end

function funcVideoSwitch(argOutNumber, argInputString)
    devNV32["hdmi.out."..argOutNumber..".select.pretty.name"].String = tblBabelFish[argInputString]
end

--loop to write the EventHandlers
for i, ctl in ipairs(arrListBox) do
  ctl.EventHandler = function()
    funcVideoDebugger("listOut0"..i, ctl.String, "user interaction")--print("listOut0"..i.." chose source "..ctl.String.." / "..tblBabelFish[ctl.String])
    funcVideoSwitch(i, ctl.String)--devNV32["hdmi.out."..i..".select.pretty.name"].String = tblBabelFish[ctl.String]
  end--for
end

funcSetNV32CodeName()
--NV32 gives a new "Pretty Name"
--translate "Pretty Name" into "Friendly Name"
--update the .String of the List Box
for i = 1, 2 do --for loop each list box...
  devNV32["hdmi.out."..i..".select.pretty.name"].EventHandler = function (ctl)
    funcVideoDebugger("NV32 Out "..i, ctl.String, "device updated")
    arrListBox[i].String = tblBabelFish[ctl.String]
  end
end

-- Routing Display and Laptop constants --
kDisplay01 = 1
kDisplay02 = 2
kLaptop01 = 1
kLaptop02 = 2

controls.pinLEDLaptop01Active.EventHandler = function (ctl)
  if ctl.Boolean then 
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop01])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop01])
  end--if 
end

controls.pinLEDLaptop02Active.EventHandler = function (ctl)
  if ctl.Boolean then
    funcVideoSwitch(kDisplay01, arrFriendlyNames[kLaptop02])
    funcVideoSwitch(kDisplay02, arrFriendlyNames[kLaptop02])
  end--if
end

function funcInit()
  varActiveLayer = kLayer_Room
  funcShowLayer()
  funcInterlock()
  funcDebugger()
  funcUpdateLegends()
  funcSetChoices()
  funcSetNV32CodeName()
  print("UCI Initialized")
end
--in the Mainline of the script and will run once at Startup
funcInit()