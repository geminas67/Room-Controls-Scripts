--[[
  ConferencingController - Q-SYS Control Script for Conference Room Management
  Author: Nikolas Smith, Q-SYS
  Date: 2025-01-27
  Version: 2.0 - Refactored Class Implementation
  Description: Manages conference room audio routing, camera privacy, and tracking
  based on phone hook status and device connections.
]]--

-------------------[ Control References ]-------------------
local controls = {
    compACPR = Controls.compACPR,
    compCallSync = Controls.compCallSync,
    devCams = Controls.devCams,
    compRoomControl = Controls.compRoomControl,
    compHidConferencing = Controls.compHidConferencing,
    txtStatus = Controls.txtStatus,   
}

-----------------[ Class Constructor ]-------------------
ConferencingController = {}
ConferencingController.__index = ConferencingController

function ConferencingController.new(roomName, config)
    local self = setmetatable({}, ConferencingController)
    self.roomName = roomName or "Conference Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        conferencingDSP = "hid_conferencing_dsp",
        conferencingIOB = "hid_conferencing_iob", 
        cameraACPR = "camera_acpr",
        cameras = "camera",
        usbLevels = "level_usb"
    }
    self.components = {
        conferencingDSP = nil,
        conferencingIOB01 = nil,
        conferencingIOB02 = nil,
        cameraACPR = nil,
        cameras = {},
        invalid = {}
    }
    self.state = {
        hidOffHook = false,
        iob01Connected = false,
        iob02Connected = false,
        trackingBypassed = false,
        currentCameraOutput = "01"
    }
    self.config = {
        defaultCameraOutput = "01",
        cameraOutputs = {
            iob01 = "02",
            iob02 = "03"
        },
        usbLevels = {
            uce = "lvlUSBUCE-01",
            table01 = "lvlUSBTable01", 
            table02 = "lvlUSBTable02"
        }
    }

    self.controls = controls
    self:initializeComponents()
    self:registerEventHandlers()
    
    return self
end

-----------------[ Debug Helper ]-------------------
function ConferencingController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." Conferencing] "..str) 
    end
end


-----------------[ Component Management ]-------------------
function ConferencingController:setComponent(ctrl, componentType)
  self:debugPrint("Setting Component: " .. componentType)
  local componentName = ctrl.String
  
  if componentName == "" then
      self:debugPrint("No " .. componentType .. " Component Selected")
      ctrl.Color = self.componentColors.white
      self:setComponentValid(componentType)
      return nil
  elseif componentName == self.clearString then
      self:debugPrint(componentType .. ": Component Cleared")
      ctrl.String = ""
      ctrl.Color = self.componentColors.white
      self:setComponentValid(componentType)
      return nil
  elseif #Component.GetControls(Component.New(componentName)) < 1 then
      self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
      ctrl.String = "[Invalid Component Selected]"
      ctrl.Color = self.componentColors.pink
      self:setComponentInvalid(componentType)
      return nil
  else
      self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
      ctrl.Color = self.componentColors.white
      self:setComponentValid(componentType)
      return Component.New(componentName)
  end
end

function ConferencingController:setComponentInvalid(componentType)
  self.state.invalidComponents[componentType] = true
  self:checkStatus()
end

function ConferencingController:setComponentValid(componentType)
  self.state.invalidComponents[componentType] = false
  self:checkStatus()
end

function ConferencingController:checkStatus()
  for i, v in pairs(self.state.invalidComponents) do
      if v == true then
          Controls.txtStatus.String = "Invalid Components"
          Controls.txtStatus.Value = 1
          return
      end
  end
  Controls.txtStatus.String = "OK"
  Controls.txtStatus.Value = 0
end

function ConferencingController:populateRoomControlsChoices()
  local names = {}
  for _, comp in pairs(Component.GetComponents()) do
      if comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls") then
          table.insert(names, comp.Name)
      end
  end
  table.sort(names)
  table.insert(names, self.clearString)
  Controls.compRoomControls.Choices = names
end

-----------------[ Component Initialization ]-------------------
function ConferencingController:initializeComponents()
    self:debugPrint("Initializing components...")
    -- Initialize core conferencing components
    self.components.conferencingDSP = self:setComponent("hidConferencingDSP01", "Conferencing DSP")
    self.components.conferencingIOB01 = self:setComponent("hidConferencingIOB01", "Conferencing IOB 01")
    self.components.conferencingIOB02 = self:setComponent("hidConferencingIOB02", "Conferencing IOB 02")
    self.components.cameraACPR = self:setComponent("camACPR", "Camera ACPR")
    -- Initialize cameras
    self.components.cameras.CAM01 = self:setComponent("CAM-01", "Camera 01")
    self.components.cameras.CAM02 = self:setComponent("CAM-02", "Camera 02") 
    self.components.cameras.CAM03 = self:setComponent("CAM-03", "Camera 03")
    -- Initialize USB level controls
    self.components.usbLevels.UCE = self:setComponent(self.config.usbLevels.uce, "USB UCE Level")
    self.components.usbLevels.Table01 = self:setComponent(self.config.usbLevels.table01, "USB Table 01 Level")
    self.components.usbLevels.Table02 = self:setComponent(self.config.usbLevels.table02, "USB Table 02 Level")
    
    self:debugPrint("Component initialization complete")
end

-----------------[ Component Helper ]-------------------
function ConferencingController:setComponent(componentName, displayName)
    if not componentName then
        self:debugPrint("ERROR: Component name is nil for " .. (displayName or "unknown"))
        return nil
    end
    
    local component = Component.New(componentName)
    if not component then
        self:debugPrint("ERROR: Failed to create component: " .. componentName)
        table.insert(self.components.invalid, {name = componentName, display = displayName})
        return nil
    end
    
    self:debugPrint("✓ " .. displayName .. " (" .. componentName .. ")")
    return component
end

-----------------[ Safe Component Access ]-------------------
function ConferencingController:safeComponentAccess(component, property, method, value)
    if not component then return false end
    
    local success, result = pcall(function()
        if method == "set" then
            component[property] = value
        elseif method == "setValue" then
            component[property] = value
        elseif method == "get" then
            return component[property]
        end
    end)
    
    if not success then
        self:debugPrint("ERROR: Failed to access " .. property .. " on component")
        return false
    end
    
    return result or true
end

-----------------[ Event Handler Registration ]-------------------
function ConferencingController:registerEventHandlers()
    self:debugPrint("Registering event handlers...")
    
    -- Phone hook status handlers
    if self.components.conferencingDSP then
        self.components.conferencingDSP['spk_led_off_hook'].EventHandler = function(ctl)
            self:handlePhoneHookStatus(ctl.Boolean)
        end
    end
    
    if self.components.conferencingIOB01 then
        self.components.conferencingIOB01['spk_led_off_hook'].EventHandler = function(ctl)
            self:handlePhoneHookStatus(ctl.Boolean)
        end
    end
    
    if self.components.conferencingIOB02 then
        self.components.conferencingIOB02['spk_led_off_hook'].EventHandler = function(ctl)
            self:handlePhoneHookStatus(ctl.Boolean)
        end
    end
    -- Camera tracking bypass handler
    if self.components.cameraACPR then
        self.components.cameraACPR['TrackingBypass'].EventHandler = function(ctl)
            self:handleTrackingBypass(ctl.Boolean)
        end
    end
    -- IOB connection status handlers
    if self.components.conferencingIOB01 then
        self.components.conferencingIOB01['spk_led_connected'].EventHandler = function(ctl)
            self:handleIOBConnectionStatus("iob01", ctl.Boolean)
        end
    end
    
    if self.components.conferencingIOB02 then
        self.components.conferencingIOB02['spk_led_connected'].EventHandler = function(ctl)
            self:handleIOBConnectionStatus("iob02", ctl.Boolean)
        end
    end
    
    self:debugPrint("Event handlers registered")
end

-----------------[ Event Handlers ]-------------------
function ConferencingController:handlePhoneHookStatus(isOffHook)
    self.state.hidOffHook = isOffHook
    self:debugPrint("Phone hook status: " .. (isOffHook and "OFF HOOK" or "ON HOOK"))
    -- Update camera privacy and tracking based on hook status
    local privacyState = not isOffHook
    local trackingBypass = isOffHook
    -- Set camera privacy
    self:setCameraPrivacy(privacyState)
    -- Set tracking bypass
    if self.components.cameraACPR then
        self:safeComponentAccess(self.components.cameraACPR, 'TrackingBypass', 'set', trackingBypass)
    end
    self:updateCameraRouting()
end

function ConferencingController:handleTrackingBypass(isBypassed)
    self.state.trackingBypassed = isBypassed
    self:debugPrint("Tracking bypass: " .. (isBypassed and "ENABLED" or "DISABLED"))
    -- Update autoframe enable based on tracking bypass
    local autoframeEnabled = not isBypassed
    self:setCameraAutoframe(autoframeEnabled)
end

function ConferencingController:handleIOBConnectionStatus(iobType, isConnected)
    if iobType == "iob01" then
        self.state.iob01Connected = isConnected
        self:debugPrint("IOB01 connection: " .. (isConnected and "CONNECTED" or "DISCONNECTED"))
    elseif iobType == "iob02" then
        self.state.iob02Connected = isConnected
        self:debugPrint("IOB02 connection: " .. (isConnected and "CONNECTED" or "DISCONNECTED"))
    end
    -- Update camera routing and USB levels
    self:updateCameraRouting()
    self:updateUSBLevels()
end

-----------------[ Camera Management ]-------------------
function ConferencingController:setCameraPrivacy(privacyEnabled)
    for cameraName, camera in pairs(self.components.cameras) do
        if camera then
            self:safeComponentAccess(camera, 'toggle_privacy', 'set', privacyEnabled)
        end
    end
end

function ConferencingController:setCameraAutoframe(autoframeEnabled)
    for cameraName, camera in pairs(self.components.cameras) do
        if camera then
            self:safeComponentAccess(camera, 'autoframe_enable', 'set', autoframeEnabled)
        end
    end
end

-----------------[ Camera Routing Logic ]-------------------
function ConferencingController:updateCameraRouting()
    if self.state.hidOffHook then
        -- Phone is off hook, use default camera output
        self.state.currentCameraOutput = self.config.defaultCameraOutput
    elseif self.state.iob01Connected then
        -- IOB01 is connected, route to camera output 02
        self.state.currentCameraOutput = self.config.cameraOutputs.iob01
    elseif self.state.iob02Connected then
        -- IOB02 is connected, route to camera output 03
        self.state.currentCameraOutput = self.config.cameraOutputs.iob02
    else
        -- No connections, use default
        self.state.currentCameraOutput = self.config.defaultCameraOutput
    end
    -- Set camera router output
    if self.components.cameraACPR then
        self:safeComponentAccess(self.components.cameraACPR, 'CameraRouterOutput', 'set', self.state.currentCameraOutput)
        self:debugPrint("Camera routing set to: " .. self.state.currentCameraOutput)
    end
end

-----------------[ USB Level Management ]-------------------
function ConferencingController:updateUSBLevels()
    -- Determine which USB level should be active based on connections
    local uceMute = true
    local table01Mute = true
    local table02Mute = true
    
    if self.state.hidOffHook then
        -- Phone is off hook, mute all except table01
        table01Mute = false
    elseif self.state.iob01Connected then
        -- IOB01 connected, mute all except table02
        table02Mute = false
    elseif self.state.iob02Connected then
        -- IOB02 connected, mute all except table02
        table02Mute = false
    else
        -- No connections, mute all except UCE
        uceMute = false
    end
    -- Apply mute states
    if self.components.usbLevels.UCE then
        self:safeComponentAccess(self.components.usbLevels.UCE, 'mute', 'set', uceMute)
    end
    
    if self.components.usbLevels.Table01 then
        self:safeComponentAccess(self.components.usbLevels.Table01, 'mute', 'set', table01Mute)
    end
    
    if self.components.usbLevels.Table02 then
        self:safeComponentAccess(self.components.usbLevels.Table02, 'mute', 'set', table02Mute)
    end
    
    self:debugPrint("USB levels updated - UCE:" .. (uceMute and "Muted" or "Active") .. 
                   " Table01:" .. (table01Mute and "Muted" or "Active") .. 
                   " Table02:" .. (table02Mute and "Muted" or "Active"))
end

-----------------[ System Status ]-------------------
function ConferencingController:getSystemStatus()
    return {
        hidOffHook = self.state.hidOffHook,
        iob01Connected = self.state.iob01Connected,
        iob02Connected = self.state.iob02Connected,
        trackingBypassed = self.state.trackingBypassed,
        currentCameraOutput = self.state.currentCameraOutput,
        components = {
            conferencingDSP = self.components.conferencingDSP ~= nil,
            conferencingIOB01 = self.components.conferencingIOB01 ~= nil,
            conferencingIOB02 = self.components.conferencingIOB02 ~= nil,
            cameraACPR = self.components.cameraACPR ~= nil,
            cameras = self:countValidComponents(self.components.cameras),
            usbLevels = self:countValidComponents(self.components.usbLevels)
        }
    }
end

function ConferencingController:countValidComponents(componentTable)
    local count = 0
    for _, component in pairs(componentTable) do
        if component then count = count + 1 end
    end
    return count
end

-----------------[ Initialization ]-------------------
-- Create and initialize the conferencing controller
local conferencingController = ConferencingController.new("Main Conference Room", {
    debugging = true
})

-- Print system status on startup
Timer.CallAfter(function()
    local status = conferencingController:getSystemStatus()
    conferencingController:debugPrint("System initialized successfully")
    conferencingController:debugPrint("Status: " .. json.encode(status))
end, 1)