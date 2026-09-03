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
    { btn = "btnNav07", hid = "usbBridgeCTL01", pgm = 1, acpr = "01", cam = "select.1" },
    { btn = "btnNav08", hid = "usbBridgeIOB01", pgm = 2, acpr = "02", cam = "select.2" },
  }
  
  -------------------[ Control References ]-------------------
  uciController = Component.New('uciController')
  roomControls  = Component.New('comRoomControls')
  rtrPGM        = Component.New('rtrPGM')
  compACPR      = Component.New('compACPR')
  compCamPreset = Component.New('camPresetsControls')
  
  function updateSourceSelection()
    for _, route in ipairs(sourceMap) do
      if uciController[route.btn].Boolean then
        roomControls['compVideoRouter 1'].String = route.hid
        rtrPGM['select.1'].Value = route.pgm
        compACPR["CameraRouterOutput"].String = route.acpr
        compCamPreset["routerOutput"].String = route.cam
        return
      end
    end
  end
  
  for _, route in ipairs(sourceMap) do
    uciController[route.btn].EventHandler = updateSourceSelection
  end
  
  updateSourceSelection()
