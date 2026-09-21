--[[
    Conferencing Source Helper
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-08-21
    Firmware Req: 10.1.0
    Notes:
    - This script is used to help the with Source Selection in Conferencing Spaces.
]]

-------------------[ Configuration ]-------------------
local sourceMap = {
    { btn = "btnNav07", hid = "usbBridgeCTL01", pgm = 1, acpr = "01", cam = "select.1", muteVis = false, micLED = "Green"},
    { btn = "btnNav08", hid = "usbBridgeIOB01", pgm = 2, acpr = "02", cam = "select.2", muteVis = true, micLED = "Black"},
  }
  
  -------------------[ Control References ]-------------------
  uciController = Component.New('uciController')
  roomControls  = Component.New('compRoomControls')
  rtrPGM        = Component.New('rtrPGM')
  compACPR      = Component.New('compACPR')
  compCamPreset = Component.New('camPresetsControls')
  genericHDMI01 = Component.New('genericHDMIMon01')
  atnd01 = Component.New('atnd01')
  atnd02 = Component.New('atnd02')
  atnd03 = Component.New('atnd03')
  
  function updateSourceSelection()
    for _, route in ipairs(sourceMap) do
      if uciController[route.btn].Boolean then
        roomControls['compVideoBridge 1'].String = route.hid
        rtrPGM['select.1'].Value = route.pgm
        compACPR["CameraRouterOutput"].String = route.acpr
        compCamPreset["routerOutput"].String = route.cam
        genericHDMI01["channel.1.output.mute.visible"].Boolean = route.muteVis
        genericHDMI01["channel.2.output.mute.visible"].Boolean = route.muteVis
        atnd01["LEDColorUnmuted"].String = route.micLED
        atnd02["LEDColorUnmuted"].String = route.micLED
        atnd03["LEDColorUnmuted"].String = route.micLED
        return
      end
    end
  end

for _, route in ipairs(sourceMap) do
    uciController[route.btn].EventHandler = updateSourceSelection
end

updateSourceSelection()
