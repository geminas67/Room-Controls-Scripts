--[[ 

  UCI Notifications Example Script - Class-Based Architecture
  Author: Nikolas Smith
  Firmware Req: 10.0.0
  Version: 3.0 - Class-Based OOP Architecture with Metatable Patterns
  
  ]] --

----* UCI Notification Controller Class *----

local UCINotificationController = {}
UCINotificationController.__index = UCINotificationController

-- Class constructor
function UCINotificationController.new()
    local self = setmetatable({}, UCINotificationController)
    
    -- Initialize instance properties
    self.sourceNumber = 3
    self.sourceCurrent = 1
    self.announcementText = ""
    self.noteID = nil
    self.AnnounceSub = nil
    self.timerHelpResponse = nil
    self.timerInit = Timer.New()
    self.blinkTimer = Timer.New()
    self.blinkCadence = 1
    
    -- Pre-cache frequently accessed controls for direct access
    self.Controls = Controls   
    self.Uci = Uci
    self.Notifications = Notifications
    self.Timer = Timer
    self.Component = Component
    
    -- Control groups for batch operations
    self.callIncomingControls = {Controls.btnCallAccept, Controls.btnCallReject}
    self.callOffHookControls = {Controls.btnDisconnect}
    self.helpRequestControls = {Controls.msgHelp}
    self.sourceButtons = {}
    self.sourceTexts = {}
    
    -- Pre-build source control arrays for faster access
    for i = 1, self.sourceNumber do
        self.sourceButtons[i] = Controls["Btn_Src_" .. i]
        self.sourceTexts[i] = Controls["Txt_Src_" .. i]
    end
    
    -- Constants
    self.HelpPrompt = "[Please Select a Help Request]"
    self.announcementID = "SystemAnnouncement"
    
    -- Dynamic component discovery and caching
    self.componentCache = {}
    
    -- Initialize event handlers
    self:setupEventHandlers()
    
    return self
end

-- Component cache with lazy loading
function UCINotificationController:getComponent(name)
    if not self.componentCache[name] then
        self.componentCache[name] = self.Component.New(name)
    end
    return self.componentCache[name]
end

-- Component references with lazy loading
function UCINotificationController:getSvgControls() 
    return self:getComponent("SVG Text Control") 
end

function UCINotificationController:getGiphify() 
    return self:getComponent("Giphify Helper") 
end

function UCINotificationController:getResponseSelect() 
    return self:getComponent("Response Select") 
end

-- Direct announcement handler with minimal processing
function UCINotificationController:announcementHandler(name, announcement)
    self.announcementText = announcement
    self.Controls.txtAnnouncement.String = announcement
    
    -- Direct timer control without function call overhead
    if announcement ~= "" then
        self.blinkTimer:Start(self.blinkCadence)
    else
        self.blinkTimer:Stop()
    end
end

-- Streamlined room notes handler with direct state updates
function UCINotificationController:roomNotesHandler(name, notes)
    local notificationType = notes.NotificationType
    local data = notes.Data
    
    if notificationType == "RoomParams" then
        self:handleRoomParams(data)
    elseif notificationType == "Volume" then
        self:handleVolume(data)
    elseif notificationType == "Power" then
        self:handlePower(data)
    elseif notificationType == "Source" then
        self:handleSource(data)
    elseif notificationType == "Call" then
        self:handleCall(data)
    elseif notificationType == "HelpResponse" then
        self:handleHelpResponse(data)
    end
end

function UCINotificationController:handleRoomParams(data)
    -- Direct room parameter updates
    if data.RoomName then self.Controls.Txt_RoomName.String = data.RoomName end
    if data.HelpHeading then self.Controls.Txt_HelpHeading.String = data.HelpHeading end
    if data.HelpDeskNumber then self.Controls.Txt_HelpNumber.String = data.HelpDeskNumber end
    
    -- Batch source updates
    if data.Sources then
        for i = 1, self.sourceNumber do
            local source = data.Sources[i]
            if source then
                self.sourceButtons[i].CssClass = source.CSS
                self.sourceTexts[i].String = source.Name
            end
        end
    end
    
    if data.helpRequests then
        self.Controls.msgHelp.Choices = data.helpRequests
    end
end

function UCINotificationController:handleVolume(data)
    -- Direct volume state updates
    local mute = data.Mute
    self.Controls.Btn_VolumeMute.Boolean = mute
    self.Controls.Fader_Volume.Position = mute and 0 or data.Volume
end

function UCINotificationController:handlePower(data)
    -- Direct power state updates
    local state = data.State
    self.Uci.SetLayerVisibility("Main", "Splash", not state, "none")
    self.Uci.SetLayerVisibility("Main", "Power On", state, "none")
end

function UCINotificationController:handleSource(data)
    -- Direct source feedback updates
    self.sourceCurrent = data.Source
    for i = 1, self.sourceNumber do
        self.sourceButtons[i].Boolean = (i == self.sourceCurrent)
    end
end

function UCINotificationController:handleCall(data)
    -- Direct call state updates with batch visibility control
    self.Controls.LED_UsbConnected.Boolean = data.UsbConnected
    self.Controls.LED_IncomingCall.Boolean = data.IncomingCall
    self.Controls.LED_OffHook.Boolean = data.OffHook
    self.Controls.Btn_VolumePrivacy.Boolean = data.Privacy
    
    -- Batch visibility updates
    local incomingVisible = data.IncomingCall
    local offHookVisible = data.OffHook
    
    for _, ctrl in ipairs(self.callIncomingControls) do
        ctrl.IsInvisible = not incomingVisible
    end
    
    for _, ctrl in ipairs(self.callOffHookControls) do
        ctrl.IsInvisible = not offHookVisible
    end
end

function UCINotificationController:handleHelpResponse(data)
    -- Direct help response handling
    self.Controls.txtHelpResponse.String = data.Response
    
    -- Check response immediately with cached component access
    local responseSelect = self:getResponseSelect()
    if data.Response == responseSelect["value"].String then
        local roomID = self.Uci.Variables.Room_ID.String
        if roomID ~= "RoomControls" and roomID ~= "Template" and roomID ~= "Boardroom" then
            self.Timer.CallAfter(function() self:greatSuccess() end, 1)
        end
    end
    
    -- Clear response after delay
    if self.timerHelpResponse then self.timerHelpResponse:Cancel() end
    self.timerHelpResponse = self.Timer.CallAfter(function()
        self.Controls.txtHelpResponse.String = ""
    end, 60)
    
    if data.Clear then
        -- Direct help state reset
        self.Controls.btnHelpRequestOn.Boolean = false
        self.Controls.btnHelpRequestOff.Boolean = true
        self.Controls.msgHelp.String = self.HelpPrompt
        for _, ctrl in ipairs(self.helpRequestControls) do
            ctrl.IsInvisible = true
        end
    end
end

-- Optimized notification publishing with direct string concatenation
function UCINotificationController:publishPanelNotification(str)
    local panelID = self.Uci.Variables.Panel_ID.String
    if panelID ~= "" then
        self.Notifications.Publish(panelID, str)
    end
end

-- Streamlined subscription management
function UCINotificationController:roomSubscribe()
    local roomID = self.Uci.Variables.Room_ID.String
    if roomID ~= "" then
        if self.noteID then self.Notifications.Unsubscribe(self.noteID) end
        self.noteID = self.Notifications.Subscribe(roomID, function(name, notes) 
            self:roomNotesHandler(name, notes) 
        end)
        self.Controls.LED_Subscribed.Boolean = self.noteID ~= nil
        self:publishPanelNotification("request_params")
    end
end

function UCINotificationController:announcementSubscribe()
    if self.AnnounceSub then self.Notifications.Unsubscribe(self.AnnounceSub) end
    self.AnnounceSub = self.Notifications.Subscribe(self.announcementID, function(name, announcement) 
        self:announcementHandler(name, announcement) 
    end)
end

-- Direct success layer management with lazy component loading
function UCINotificationController:hideSuccessLayer()
    self.Uci.SetLayerVisibility("Main", "Help Desk", false, "none")
    self.Controls.txtHelpResponse.String = ""
    self:getSvgControls()["SVG"].IsInvisible = true
    self:getGiphify()["Animated Button"].IsInvisible = true
end

function UCINotificationController:greatSuccess()
    self:getSvgControls()["SVG"].IsInvisible = false
    self:getGiphify()["Animated Button"].IsInvisible = false
    self.Uci.SetLayerVisibility("Main", "Help Desk", true, "right")
end

-- Setup all event handlers
function UCINotificationController:setupEventHandlers()
    -- Direct blink timer handler
    self.blinkTimer.EventHandler = function()
        local currentText = self.Controls.txtAnnouncement.String
        self.Controls.txtAnnouncement.String = (currentText == "") and self.announcementText or ""
        self.blinkTimer:Start(self.blinkCadence)
    end
    
    -- Streamlined power controls with immediate visual feedback
    self.Controls.Btn_Splash.EventHandler = function()
        self.Uci.SetLayerVisibility("Main", "Splash", false, "none")
        self.Uci.SetLayerVisibility("Main", "Power On", true, "none")
        self:publishPanelNotification("set_power_true")
    end
    
    self.Controls.Btn_PowerOff.EventHandler = function()
        self.Uci.SetLayerVisibility("Main", "Splash", true, "none")
        self.Uci.SetLayerVisibility("Main", "Power On", false, "none")
        self:publishPanelNotification("set_power_false")
    end
    
    -- Direct source selection with immediate feedback
    for i = 1, self.sourceNumber do
        self.sourceButtons[i].EventHandler = function()
            self.sourceCurrent = i
            -- Immediate visual feedback
            for j = 1, self.sourceNumber do
                self.sourceButtons[j].Boolean = (j == i)
            end
            self:publishPanelNotification("set_src_" .. i)
        end
    end
    
    -- Direct volume controls
    self.Controls.Btn_VolumeMute.EventHandler = function(ctl)
        self:publishPanelNotification("set_volume_mute_" .. tostring(ctl.Boolean))
    end
    
    self.Controls.Fader_Volume.EventHandler = function(ctl)
        self:publishPanelNotification("set_volume_lvl_" .. tostring(ctl.Position))
    end
    
    self.Controls.Btn_VolumePrivacy.EventHandler = function(ctl)
        self:publishPanelNotification("set_privacy_" .. tostring(ctl.Boolean))
    end
    
    -- Direct call controls
    self.Controls.btnCallAccept.EventHandler = function()
        self:publishPanelNotification("call_accept")
    end
    
    self.Controls.btnCallReject.EventHandler = function()
        self:publishPanelNotification("call_decline")
    end
    
    self.Controls.btnDisconnect.EventHandler = function()
        self:publishPanelNotification("call_decline")
    end
    
    -- Streamlined help controls with immediate state updates
    self.Controls.btnHelpRequestOn.EventHandler = function()
        self.Controls.btnHelpRequestOn.Boolean = true
        self.Controls.btnHelpRequestOff.Boolean = false
        self.Controls.msgHelp.IsInvisible = false
        self:publishPanelNotification("help_request_true")
    end
    
    self.Controls.btnHelpRequestOff.EventHandler = function()
        self.Controls.btnHelpRequestOn.Boolean = false
        self.Controls.btnHelpRequestOff.Boolean = true
        self.Controls.msgHelp.IsInvisible = true
        self.Controls.msgHelp.String = self.HelpPrompt
        self:publishPanelNotification("help_request_false")
    end
    
    self.Controls.msgHelp.EventHandler = function(ctl)
        self:publishPanelNotification("help_request_msg_" .. ctl.String)
    end
    
    -- Direct success layer control
    self.Controls.Btn_DontDill.EventHandler = function()
        self:hideSuccessLayer()
    end
    
    -- Variable change handlers
    self.Uci.Variables.Panel_ID.EventHandler = function()
        self:roomSubscribe()
    end
    
    self.Uci.Variables.Room_ID.EventHandler = function()
        self:roomSubscribe()
    end
    
    -- Single initialization timer for all delayed tasks
    self.timerInit.EventHandler = function()
        self:initialize()
        self.timerInit:Cancel()
    end
end

-- Initialize the controller
function UCINotificationController:initialize()
    -- Batch all initialization tasks
    self:announcementSubscribe()
    self:roomSubscribe()
    
    -- Direct initial state setup
    for _, ctrl in ipairs(self.callIncomingControls) do
        ctrl.IsInvisible = true
    end
    
    for _, ctrl in ipairs(self.callOffHookControls) do
        ctrl.IsInvisible = true
    end
    
    self.Controls.btnHelpRequestOn.Boolean = false
    self.Controls.btnHelpRequestOff.Boolean = true
    self.Controls.msgHelp.IsInvisible = true
    self.Controls.msgHelp.String = self.HelpPrompt
    
    self:hideSuccessLayer()
end

-- Start the controller
function UCINotificationController:start()
    self.timerInit:Start(0.1)
end

----* Instance Creation and Startup *----

-- Create the main controller instance
local uciController = UCINotificationController.new()

-- Start the controller
uciController:start()

--[[
Copyright 2024 QSC, LLC
Permission is hereby granted, free of charge, to any person obtaining a copy 
of this softwareand associated documentation files (the "Software"), to deal 
in the Software without restriction, including without limitation the rights 
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]] --
                                               
