--[[
  NV32-UCI Integration Example
  Author: Nikolas Smith, Q-SYS
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.0

  This example demonstrates how the NV32RouterController automatically
  switches inputs based on UCI navigation button states.
]]--

--[[
  AUTOMATIC INTEGRATION:
  When both myUCI and myNV32RouterController exist, they automatically connect.
  
  The NV32RouterController will automatically switch inputs when these UCI buttons are active:
  - Controls.btnNav07.Boolean = true → switches to HDMI2 (Graphic2)
  - Controls.btnNav08.Boolean = true → switches to HDMI1 (Graphic1)  
  - Controls.btnNav09.Boolean = true → switches to HDMI3 (Graphic3)
]]--

--[[
  MANUAL INTEGRATION (if needed):
  If you need to manually connect the controllers, use these commands:
  
  -- Connect NV32RouterController to UCIController
  myUCI:registerExternalController(myNV32RouterController, "NV32Router")
  
  -- Set UCI controller reference in NV32RouterController
  myNV32RouterController:setUCIController(myUCI)
  
  -- Enable/disable UCI integration
  myNV32RouterController:enableUCIIntegration()
  myNV32RouterController:disableUCIIntegration()
]]--

--[[
  HOW IT WORKS:
  1. When a user presses btnNav07, btnNav08, or btnNav09 on the UCI:
     - The UCIController changes to the corresponding layer (7, 8, or 9)
     - The UCIController notifies all registered external controllers
     - The NV32RouterController receives the notification via onUCILayerChange()
     - The NV32RouterController automatically switches the NV32 input
  
  2. The NV32RouterController also has direct button monitoring as a backup:
     - It directly monitors Controls.btnNav07, btnNav08, btnNav09
     - This provides immediate response even if the notification system fails
  
  3. Both methods work simultaneously for maximum reliability
]]--

--[[
  DEBUGGING:
  Enable debug output in NV32RouterController by setting:
  myNV32RouterController.debugging = true
  
  This will show:
  - When UCI layers change
  - When input switching occurs
  - Component connection status
]]--

print("NV32-UCI Integration Example loaded")
print("Automatic input switching will occur when UCI navigation buttons 7, 8, or 9 are active")

--[[
  EXPECTED BEHAVIOR:
  - Press btnNav07 on UCI → NV32 Output 1 switches to HDMI2 (Graphic2)
  - Press btnNav08 on UCI → NV32 Output 1 switches to HDMI1 (Graphic1)
  - Press btnNav09 on UCI → NV32 Output 1 switches to HDMI3 (Graphic3)
  
  The switching happens automatically without any additional code needed!
]]-- 