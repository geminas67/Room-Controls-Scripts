--[[
    UCIController (Functional/Modular Refactor)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2025-12-05
    Firmware Req: 10.0.0
    Notes:
    - Refactored from OOP to functional/modular pattern using factory functions
    - State managed via closures instead of class fields
    - Explicit dependencies passed to each module
    - Same functionality with reduced boilerplate
    - Aligned with modern Lua idioms and Svelte-like logic module patterns
]]

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Buttons
    btnNav01 = Controls.btnNav01, btnNav02 = Controls.btnNav02, btnNav03 = Controls.btnNav03,
    btnNav04 = Controls.btnNav04, btnNav05 = Controls.btnNav05, btnNav06 = Controls.btnNav06,
    btnNav07 = Controls.btnNav07, btnNav08 = Controls.btnNav08, btnNav09 = Controls.btnNav09,
    btnNav10 = Controls.btnNav10, btnNav11 = Controls.btnNav11, btnNav12 = Controls.btnNav12,
    
    -- System Controls
    btnStartSystem      = Controls.btnStartSystem,
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel,
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    
    -- Help Buttons
    btnOpenHelpLaptop       = Controls.btnOpenHelpLaptop,
    btnOpenHelpPC           = Controls.btnOpenHelpPC,
    btnOpenHelpWireless     = Controls.btnOpenHelpWireless,
    btnOpenHelpRouting      = Controls.btnOpenHelpRouting,
    btnOpenHelpStreamMusic  = Controls.btnOpenHelpStreamMusic,
    
    btnCloseHelpLaptop      = Controls.btnCloseHelpLaptop,
    btnCloseHelpPC          = Controls.btnCloseHelpPC,
    btnCloseHelpWireless    = Controls.btnCloseHelpWireless,
    btnCloseHelpRouting     = Controls.btnCloseHelpRouting,
    btnCloseHelpStreamMusic = Controls.btnCloseHelpStreamMusic,
    
    -- Routing Buttons
    btnRouting01 = Controls.btnRouting01, btnRouting02 = Controls.btnRouting02,
    btnRouting03 = Controls.btnRouting03, btnRouting04 = Controls.btnRouting04, 
    btnRouting05 = Controls.btnRouting05,
    
    -- Progress Controls
    knbProgressBar = Controls.knbProgressBar,
    txtProgressBar = Controls.txtProgressBar,
    
    -- Pin Inputs
    pinCallActive           = Controls.pinCallActive,
    pinLEDUSBLaptop         = Controls.pinLEDUSBLaptop,
    pinLEDUSBPC             = Controls.pinLEDUSBPC,
    pinLEDOffHookLaptop     = Controls.pinLEDOffHookLaptop,
    pinLEDOffHookPC         = Controls.pinLEDOffHookPC,
    pinLEDHDMI01Active      = Controls.pinLEDHDMI01Active,
    pinLEDHDMI02Active      = Controls.pinLEDHDMI02Active,
    pinLEDPresetSaved       = Controls.pinLEDPresetSaved,
    pinLEDHDMI01Connect     = Controls.pinLEDHDMI01Connect,
    pinLEDHDMI02Connect     = Controls.pinLEDHDMI02Connect,
    pinLEDACPRBypassActive  = Controls.pinLEDACPRBypassActive,
}

-------------------[ Layer Constants ]----------------------
local LAYERS = {
    ALARM           = 1,
    INCOMING_CALL   = 2,
    START           = 3,
    WARMING         = 4,
    COOLING         = 5,
    ROOM_CONTROLS   = 6,
    PC              = 7,
    LAPTOP          = 8,
    WIRELESS        = 9,
    ROUTING         = 10,
    DIALER          = 11,
    STREAM_MUSIC    = 12,
}

-------------------[ Utility Functions ]-------------------
local function isArr(t) return type(t) == "table" and t[1] ~= nil end
local function getControlArray(ctrl) return isArr(ctrl) and ctrl or (type(ctrl) == "table" and {ctrl} or {}) end

local function setProp(ctrl, prop, val)
    if not ctrl or not prop then return false end
    if ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler) 
    if ctrl and handler then ctrl.EventHandler = handler end 
end

local function bindPairedControls(openCtrl, closeCtrl, updateHandler)
    if openCtrl and updateHandler then
        bind(openCtrl, function()
            if closeCtrl then setProp(closeCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
    if closeCtrl and updateHandler then
        bind(closeCtrl, function()
            if openCtrl then setProp(openCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
end

local function forEach(arr, fn)
    if not arr or not fn then return end
    for i, item in ipairs(arr) do
        if item then fn(i, item) end
    end
end

-------------------[ Validation ]---------------------------
local function validateControls()
    local required = {
        "btnNav01", "btnNav02", "btnNav03", "btnNav04", "btnNav05", "btnNav06",
        "btnNav07", "btnNav08", "btnNav09", "btnNav10", "btnNav11", "btnNav12",
        "btnStartSystem", "btnNavShutdown", "btnShutdownCancel", "btnShutdownConfirm"
    }
    
    local optional = {
        "knbProgressBar", "txtProgressBar",
        "btnOpenHelpLaptop", "btnOpenHelpPC", "btnOpenHelpWireless", "btnOpenHelpRouting", "btnOpenHelpStreamMusic",
        "btnCloseHelpLaptop", "btnCloseHelpPC", "btnCloseHelpWireless", "btnCloseHelpRouting", "btnCloseHelpStreamMusic",
        "btnRouting01", "btnRouting02", "btnRouting03", "btnRouting04", "btnRouting05"
    }
    
    local missing, warnings = {}, {}
    
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    
    for _, name in ipairs(optional) do
        if not controls[name] then table.insert(warnings, name) end
    end
    
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    
    if #warnings > 0 then
        print("WARNING: UCIController - Missing optional controls (reduced functionality):")
        for _, name in ipairs(warnings) do print("  - " .. name) end
    end
    
    print("UCIController validation passed - All required controls found")
    return true
end

-------------------[ Control Normalization ]----------------
local function normalizeControlArrays()
    local normalized = { navButtons = {}, routingButtons = {}, helpButtons = {}, pinInputs = {} }
    
    for i = 1, 12 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then normalized.navButtons[i] = btn end
    end
    
    for i = 1, 5 do
        local btn = controls["btnRouting" .. string.format("%02d", i)]
        if btn then normalized.routingButtons[i] = btn end
    end
    
    return normalized
end

-------------------[ Debug Factory ]------------------------
local function createDebugger(ctx, moduleName)
    return function(msg)
        if ctx.debugging then
            print("[" .. ctx.uciPage .. " - " .. moduleName .. "] " .. msg)
        end
    end
end

-------------------[ Layer Module ]--------------------------
local function createLayerModule(ctx)
    local layerStates = {}
    local debug = createDebugger(ctx, "Layer")
    
    local function safeSetLayerVisibility(layer, visible, transition)
        local success, err = pcall(function()
            Uci.SetLayerVisibility(ctx.uciPage, layer, visible, transition or "none")
        end)
        if success then
            debug("Layer '" .. layer .. "' set to " .. tostring(visible))
            layerStates[layer] = visible
        else
            debug("Warning: Layer '" .. layer .. "' not found: " .. tostring(err))
        end
        return success
    end
    
    local function updateLayerVisibility(layers, visible, transition)
        if not layers or #layers == 0 or visible == nil then return end
        for _, layer in ipairs(layers) do
            if layer then
                local currentState = layerStates[layer]
                if not ctx.state.isInitialized or currentState ~= visible then
                    safeSetLayerVisibility(layer, visible, transition)
                end
            end
        end
    end
    
    local function hideBaseLayers()
        updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
    end
    
    local function resetLayerStates()
        layerStates = {}
        debug("Layer states reset")
    end
    
    local function showLayer()
        local layersToHide = {
            "A01-Alarm", "B01-IncomingCall", "C05-Start", "D01-ShutdownConfirm",
            "E01-SystemProgressWarming", "E02-SystemProgressCooling", "E05-SystemProgress",
            "H01-RoomControls", 
            "I01-CallActive", "I02-HelpLaptop", "I03-HelpPC", "I04-HelpWireless", "I05-HelpRouting", "I07-HelpStreamMusic",
            "J01-ConnectUSBLaptop", "J02-ConnectUSBPC", "J03-ACPRActive", "J04-CamPresetSaved", "J05-ConferenceControls", 
            "L01-HDMI01Disconnected", "L05-Laptop",
            "P01-HDMI02Disconnected", "P05-PC", "W05-Wireless",
            "R01-Routing01", "R02-Routing02", "R03-Routing03", "R04-Routing04", "R05-Routing05", "R10-Routing",
            "S05-StreamMusic", "V05-Dialer", 
            "X01-ProgramVolume", "Y01-Navbar", "Z01-Base"
        }
        
        for _, layer in ipairs(layersToHide) do
            updateLayerVisibility({layer}, false, "none")
        end
        
        updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")
        
        local layerConfigs = {
            [LAYERS.ALARM] = {
                showLayers = {"A01-Alarm"},
                callFunctions = {hideBaseLayers}
            },
            [LAYERS.INCOMING_CALL] = {
                showLayers = {"B01-IncomingCall"}
            },
            [LAYERS.START] = {
                showLayers = {"C05-Start"},
                callFunctions = {hideBaseLayers}
            },
            [LAYERS.WARMING] = {
                showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
                callFunctions = {hideBaseLayers}
            },
            [LAYERS.COOLING] = {
                showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
                callFunctions = {hideBaseLayers}
            },
            [LAYERS.ROOM_CONTROLS] = {
                showLayers = {"H01-RoomControls"},
                hideLayers = {"X01-ProgramVolume"},
                callFunctions = {function() ctx.sublayer.updateCallActiveState() end}
            },
            [LAYERS.LAPTOP] = {
                showLayers = {"L05-Laptop"},
                callFunctions = {
                    function() ctx.sublayer.updateHDMI01State() end,
                    function() ctx.sublayer.updateConferenceState() end,
                    function() ctx.sublayer.updatePresetSavedState() end,
                    function() ctx.sublayer.updateACPRBypassState() end,
                    function() ctx.sublayer.updateLaptopHelpState() end,
                    function() ctx.sublayer.updateCallActiveState() end
                }
            },
            [LAYERS.PC] = {
                showLayers = {"P05-PC"},
                callFunctions = {
                    function() ctx.sublayer.updateHDMI02State() end,
                    function() ctx.sublayer.updateConferenceState() end,
                    function() ctx.sublayer.updatePresetSavedState() end,
                    function() ctx.sublayer.updateACPRBypassState() end,
                    function() ctx.sublayer.updatePCHelpState() end,
                    function() ctx.sublayer.updateCallActiveState() end
                }
            },
            [LAYERS.WIRELESS] = {
                showLayers = {"W05-Wireless"},
                callFunctions = {
                    function() ctx.sublayer.updateWirelessHelpState() end,
                    function() ctx.sublayer.updateCallActiveState() end
                }
            },
            [LAYERS.ROUTING] = {
                showLayers = {"R10-Routing"},
                callFunctions = {
                    function() ctx.sublayer.updateRoutingHelpState() end,
                    function() ctx.routing.showRoutingLayer() end,
                    function() ctx.sublayer.updateCallActiveState() end
                }
            },
            [LAYERS.DIALER] = {
                showLayers = {"V05-Dialer"},
                callFunctions = {function() ctx.sublayer.updateCallActiveState() end}
            },
            [LAYERS.STREAM_MUSIC] = {
                showLayers = {"S05-StreamMusic"},
                callFunctions = {
                    function() ctx.sublayer.updateStreamMusicHelpState() end,
                    function() ctx.sublayer.updateCallActiveState() end
                }
            }
        }
        
        local config = layerConfigs[ctx.state.activeLayer]
        if not config then return end
        
        for _, layer in ipairs(config.showLayers or {}) do
            updateLayerVisibility({layer}, true, "fade")
        end
        
        for _, layer in ipairs(config.hideLayers or {}) do
            updateLayerVisibility({layer}, false, "none")
        end
        
        for _, func in ipairs(config.callFunctions or {}) do
            func()
        end
    end
    
    return {
        safeSetLayerVisibility = safeSetLayerVisibility,
        updateLayerVisibility = updateLayerVisibility,
        hideBaseLayers = hideBaseLayers,
        showLayer = showLayer,
        resetLayerStates = resetLayerStates,
    }
end

-------------------[ Sublayer Module ]-----------------------
local function createSublayerModule(ctx)
    local debug = createDebugger(ctx, "Sublayer")
    
    local function updateCallActiveState()
        if not controls.pinCallActive then return end
        local isActive = controls.pinCallActive.Boolean or false
        ctx.layer.updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
        debug("Call Active: " .. (isActive and "Showing" or "Hiding") .. " I01-CallActive")
    end
    
    local function updatePresetSavedState()
        local isVisible = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
        ctx.layer.updateLayerVisibility({"J04-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
        debug("Preset Saved: " .. (isVisible and "Showing" or "Hiding") .. " J04-CamPresetSaved")
    end
    
    local function updateHDMI01State()
        if ctx.state.activeLayer ~= LAYERS.LAPTOP then return end
        if not controls.pinLEDHDMI01Connect then return end
        local isConnected = controls.pinLEDHDMI01Connect.Boolean or false
        if isConnected then
            ctx.layer.updateLayerVisibility({"L05-Laptop"}, true, "fade")
            ctx.layer.updateLayerVisibility({"L01-HDMI01Disconnected"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({"L01-HDMI01Disconnected"}, true, "fade")
            ctx.layer.updateLayerVisibility({"L05-Laptop", "J03-ACPRActive", "J05-ConferenceControls"}, false, "none")
        end
        debug("HDMI01: " .. (isConnected and "Connected" or "Disconnected"))
    end
    
    local function updateHDMI02State()
        if ctx.state.activeLayer ~= LAYERS.PC then return end
        if not controls.pinLEDHDMI02Connect then return end
        local isConnected = controls.pinLEDHDMI02Connect.Boolean or false
        if isConnected then
            ctx.layer.updateLayerVisibility({"P05-PC"}, true, "fade")
            ctx.layer.updateLayerVisibility({"P01-HDMI02Disconnected"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({"P01-HDMI02Disconnected"}, true, "fade")
            ctx.layer.updateLayerVisibility({"P05-PC", "J03-ACPRActive", "J05-ConferenceControls"}, false, "none")
        end
        debug("HDMI02: " .. (isConnected and "Connected" or "Disconnected"))
    end
    
    local function updateACPRBypassState()
        local activeLayer = ctx.state.activeLayer
        if activeLayer ~= LAYERS.LAPTOP and activeLayer ~= LAYERS.PC then return end
        
        local isBypassActive = controls.pinLEDACPRBypassActive and controls.pinLEDACPRBypassActive.Boolean or false
        local isCallActive = controls.pinCallActive and controls.pinCallActive.Boolean or false
        
        -- Check HDMI connection for current layer
        if activeLayer == LAYERS.LAPTOP then
            if not controls.pinLEDHDMI01Connect or not controls.pinLEDHDMI01Connect.Boolean then
                ctx.layer.updateLayerVisibility({"J03-ACPRActive"}, false, "none")
                return
            end
        elseif activeLayer == LAYERS.PC then
            if not controls.pinLEDHDMI02Connect or not controls.pinLEDHDMI02Connect.Boolean then
                ctx.layer.updateLayerVisibility({"J03-ACPRActive"}, false, "none")
                return
            end
        end
        
        if not isBypassActive and isCallActive then
            ctx.layer.updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, isBypassActive, isBypassActive and "fade" or "none")
            ctx.layer.updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        end
        debug("ACPR Bypass: " .. (isBypassActive and "Active" or "Inactive") .. " | Call: " .. (isCallActive and "Active" or "Inactive"))
    end
    
    local function updateConferenceState()
        local activeLayer = ctx.state.activeLayer
        
        -- Check HDMI connection for current layer
        if activeLayer == LAYERS.LAPTOP then
            if not controls.pinLEDHDMI01Connect or not controls.pinLEDHDMI01Connect.Boolean then
                ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, false, "none")
                return
            end
        elseif activeLayer == LAYERS.PC then
            if not controls.pinLEDHDMI02Connect or not controls.pinLEDHDMI02Connect.Boolean then
                ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, false, "none")
                return
            end
        else
            return
        end
        
        local usbConnected, usbNotConnectedLayer
        if activeLayer == LAYERS.LAPTOP then
            usbConnected = controls.pinLEDUSBLaptop and controls.pinLEDUSBLaptop.Boolean or false
            usbNotConnectedLayer = "J01-ConnectUSBLaptop"
        elseif activeLayer == LAYERS.PC then
            usbConnected = controls.pinLEDUSBPC and controls.pinLEDUSBPC.Boolean or false
            usbNotConnectedLayer = "J02-ConnectUSBPC"
        else
            return
        end
        
        if usbConnected then
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, true, "fade")
            ctx.layer.updateLayerVisibility({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({usbNotConnectedLayer}, true, "fade")
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls"}, false, "none")
        end
        debug("USB: " .. (usbConnected and "Connected" or "Disconnected"))
    end
    
    local function updateLaptopHelpState()
        local isVisible = controls.btnOpenHelpLaptop and controls.btnOpenHelpLaptop.Boolean or false
        if isVisible then
            ctx.layer.updateLayerVisibility({"I02-HelpLaptop"}, true, "fade")
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({"I02-HelpLaptop"}, false, "none")
            updateConferenceState()
        end
        debug("Laptop Help: " .. (isVisible and "Showing" or "Hiding"))
    end
    
    local function updatePCHelpState()
        local isVisible = controls.btnOpenHelpPC and controls.btnOpenHelpPC.Boolean or false
        if isVisible then
            ctx.layer.updateLayerVisibility({"I03-HelpPC"}, true, "fade")
            ctx.layer.updateLayerVisibility({"J05-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        else
            ctx.layer.updateLayerVisibility({"I03-HelpPC"}, false, "none")
            updateConferenceState()
        end
        debug("PC Help: " .. (isVisible and "Showing" or "Hiding"))
    end
    
    local function updateWirelessHelpState()
        local isVisible = controls.btnOpenHelpWireless and controls.btnOpenHelpWireless.Boolean or false
        ctx.layer.updateLayerVisibility({"I04-HelpWireless"}, isVisible, "none")
        debug("Wireless Help: " .. (isVisible and "Showing" or "Hiding"))
    end
    
    local function updateRoutingHelpState()
        local isVisible = controls.btnOpenHelpRouting and controls.btnOpenHelpRouting.Boolean or false
        ctx.layer.updateLayerVisibility({"I05-HelpRouting"}, isVisible, "none")
        debug("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
    end
    
    local function updateStreamMusicHelpState()
        local isVisible = controls.btnOpenHelpStreamMusic and controls.btnOpenHelpStreamMusic.Boolean or false
        ctx.layer.updateLayerVisibility({"I07-HelpStreamMusic"}, isVisible, "none")
        debug("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
    end
    
    return {
        updateCallActiveState = updateCallActiveState,
        updatePresetSavedState = updatePresetSavedState,
        updateHDMI01State = updateHDMI01State,
        updateHDMI02State = updateHDMI02State,
        updateACPRBypassState = updateACPRBypassState,
        updateConferenceState = updateConferenceState,
        updateLaptopHelpState = updateLaptopHelpState,
        updatePCHelpState = updatePCHelpState,
        updateWirelessHelpState = updateWirelessHelpState,
        updateRoutingHelpState = updateRoutingHelpState,
        updateStreamMusicHelpState = updateStreamMusicHelpState,
    }
end

-------------------[ Routing Module ]------------------------
local function createRoutingModule(ctx)
    local debug = createDebugger(ctx, "Routing")
    local routingLayers = {"R01-Routing01", "R02-Routing02", "R03-Routing03", "R04-Routing04", "R05-Routing05"}
    local activeRoutingLayer = ctx.config.defaultRoutingLayer or 1
    
    local function getRoutingButtons()
        return {controls.btnRouting01, controls.btnRouting02, controls.btnRouting03, 
                controls.btnRouting04, controls.btnRouting05}
    end
    
    local function interlockRoutingButtons()
        for i, btn in ipairs(getRoutingButtons()) do
            if btn then btn.Boolean = (i == activeRoutingLayer) end
        end
    end
    
    local function showRoutingLayer()
        if activeRoutingLayer < 1 or activeRoutingLayer > #routingLayers then
            activeRoutingLayer = 1
        end
        
        ctx.layer.updateLayerVisibility({"X01-ProgramVolume"}, false, "none")
        
        for _, layer in ipairs(routingLayers) do
            ctx.layer.updateLayerVisibility({layer}, false, "none")
        end
        
        ctx.layer.updateLayerVisibility({routingLayers[activeRoutingLayer]}, true, "fade")
        interlockRoutingButtons()
    end
    
    local function routingButtonEventHandler(buttonIndex)
        if buttonIndex < 1 or buttonIndex > #routingLayers then
            debug("Invalid routing button index: " .. tostring(buttonIndex))
            return
        end
        activeRoutingLayer = buttonIndex
        showRoutingLayer()
        debug("Routing layer switched to: " .. routingLayers[buttonIndex])
    end
    
    local function resetRoutingButtons()
        interlockRoutingButtons()
    end
    
    local function setActiveRoutingLayer(layer)
        activeRoutingLayer = layer
    end
    
    return {
        showRoutingLayer = showRoutingLayer,
        routingButtonEventHandler = routingButtonEventHandler,
        resetRoutingButtons = resetRoutingButtons,
        setActiveRoutingLayer = setActiveRoutingLayer,
    }
end

-------------------[ Video Switcher Module ]-----------------
local function createVideoSwitcherModule(ctx)
    local debug = createDebugger(ctx, "VideoSwitcher")
    
    local switcherTypes = {
        NV32 = {
            componentType = "streamer_hdmi_switcher",
            switcherNames = {"devNV32", "codenameNV32", "varNV32"},
            routingMethod = "hdmi.out.1.select.index",
            defaultMapping = {[7] = 5, [8] = 4, [9] = 6}
        },
        ExtronDXP = {
            componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
            switcherNames = {"devExtronDXP", "codenameExtronDXP", "varExtronDXP"},
            routingMethod = "output.1",
            defaultMapping = {[7] = 2, [8] = 4, [9] = 1}
        }
    }
    
    local isEnabled = false
    local switcherComponent = nil
    local switcherType = nil
    local uciToInputMapping = {}
    
    local function autoDetectSwitcher()
        for sType, config in pairs(switcherTypes) do
            for _, switchName in ipairs(config.switcherNames) do
                if Controls[switchName] and Controls[switchName].String ~= "" then
                    return sType, Controls[switchName].String
                end
            end
        end
        
        local components = Component.GetComponents()
        for sType, config in pairs(switcherTypes) do
            for _, comp in pairs(components) do
                if comp.Type == config.componentType then
                    return sType, comp.Name
                end
            end
        end
        
        return nil, nil
    end
    
    local function initialize()
        local detectedType, componentName = autoDetectSwitcher()
        if not detectedType then
            debug("No video switcher detected")
            return false
        end
        
        local success, component = pcall(function() return Component.New(componentName) end)
        if not success or not component then
            debug("Failed to create switcher component: " .. componentName)
            return false
        end
        
        switcherType = detectedType
        switcherComponent = component
        uciToInputMapping = switcherTypes[detectedType].defaultMapping
        isEnabled = true
        debug("Video switcher initialized: " .. detectedType)
        return true
    end
    
    local function switchToInput(inputNumber, uciButton)
        if not isEnabled or not switcherComponent or not inputNumber then return false end
        
        debug("Switching to input " .. inputNumber .. " via UCI button " .. (uciButton or "unknown"))
        
        local success, err = pcall(function()
            local config = switcherTypes[switcherType]
            if not config then return false end
            
            if switcherType == "NV32" then
                setProp(switcherComponent[config.routingMethod], "Value", inputNumber)
            else
                setProp(switcherComponent[config.routingMethod], "String", tostring(inputNumber))
            end
            return true
        end)
        
        if not success then
            debug("Failed to switch: " .. tostring(err))
            return false
        end
        
        debug("Successfully switched to input " .. inputNumber)
        return true
    end
    
    local function getInputMapping(layerIndex)
        return uciToInputMapping[layerIndex]
    end
    
    local function getIsEnabled()
        return isEnabled
    end
    
    return {
        initialize = initialize,
        switchToInput = switchToInput,
        getInputMapping = getInputMapping,
        isEnabled = getIsEnabled,
    }
end

-------------------[ Room Automation Module ]----------------
local function createRoomAutomationModule(ctx)
    local debug = createDebugger(ctx, "RoomAutomation")
    
    local roomControlsComponent = nil
    local previousPowerState = nil
    
    local function initializeComponent()
        local componentName = nil
        
        if Uci.Variables.compRoomControls then
            componentName = Uci.Variables.compRoomControls.String
        end
        
        if not componentName then
            local pageName = ctx.uciPage:match("uci%s+([^(]+)")
            if pageName then
                componentName = "compRoomControls" .. pageName:gsub("%s+", "")
            end
        end
        
        if not componentName then
            debug("Could not determine Room Controls component name")
            return false
        end
        
        local success, component = pcall(function() return Component.New(componentName) end)
        if success and component then
            roomControlsComponent = component
            debug("Room Controls Component referenced: " .. componentName)
            
            if roomControlsComponent["ledSystemPower"] then
                previousPowerState = roomControlsComponent["ledSystemPower"].Boolean
                debug("Initial power state: " .. tostring(previousPowerState))
            end
            return true
        else
            debug("Room Controls Component not found: " .. componentName)
            return false
        end
    end
    
    local function powerOn()
        if not roomControlsComponent or not roomControlsComponent["btnSystemOnOff"] then
            debug("Cannot power on: Room Controls component not available")
            return false
        end
        
        local ok, result = pcall(function()
            roomControlsComponent["btnSystemOnOff"].Boolean = true
            return roomControlsComponent["btnSystemOnOff"].Boolean
        end)
        
        if ok and result then
            debug("Room powered ON")
            return true
        end
        debug("Failed to power on room automation")
        return false
    end
    
    local function powerOff()
        if not roomControlsComponent or not roomControlsComponent["btnSystemOnOff"] then
            debug("Cannot power off: Room Controls component not available")
            return false
        end
        
        local ok, result = pcall(function()
            roomControlsComponent["btnSystemOnOff"].Boolean = false
            return not roomControlsComponent["btnSystemOnOff"].Boolean
        end)
        
        if ok and result then
            debug("Room powered OFF")
            return true
        end
        debug("Failed to power off room automation")
        return false
    end
    
    local function getTiming(isPoweringOn)
        if roomControlsComponent then
            local success, result = pcall(function()
                if isPoweringOn then
                    return roomControlsComponent["warmupTime"] and roomControlsComponent["warmupTime"].Value or 10
                else
                    return roomControlsComponent["cooldownTime"] and roomControlsComponent["cooldownTime"].Value or 5
                end
            end)
            if success and result then
                debug("Using component timing: " .. result .. " seconds")
                return result
            end
        end
        
        local duration = isPoweringOn and 
            (tonumber(Uci.Variables.timeProgressWarming) or 10) or
            (tonumber(Uci.Variables.timeProgressCooling) or 5)
        
        debug("Using UCI timing: " .. duration .. " seconds")
        return duration
    end
    
    local function syncRoomControlsState()
        if not roomControlsComponent or not roomControlsComponent["ledSystemPower"] then return end
        
        local currentState = roomControlsComponent["ledSystemPower"].Boolean
        if currentState == previousPowerState then return end
        
        debug("Power state changed: " .. tostring(previousPowerState) .. " -> " .. tostring(currentState))
        previousPowerState = currentState
        
        if currentState then
            ctx.progress.startLoadingBar(true)
            ctx.navigate(LAYERS.WARMING)
            debug("Synchronized to WARMING state")
        else
            ctx.progress.startLoadingBar(false)
            ctx.navigate(LAYERS.COOLING)
            debug("Synchronized to COOLING state")
        end
    end
    
    local function getComponent()
        return roomControlsComponent
    end
    
    return {
        initializeComponent = initializeComponent,
        powerOn = powerOn,
        powerOff = powerOff,
        getTiming = getTiming,
        syncRoomControlsState = syncRoomControlsState,
        getComponent = getComponent,
    }
end

-------------------[ Progress Module ]-----------------------
local function createProgressModule(ctx)
    local debug = createDebugger(ctx, "Progress")
    
    local isAnimating = false
    local loadingTimer = nil
    local timeoutTimer = nil
    
    local function cleanup()
        if loadingTimer then loadingTimer:Stop(); loadingTimer = nil end
        if timeoutTimer then timeoutTimer:Stop(); timeoutTimer = nil end
        isAnimating = false
        debug("Progress module cleanup complete")
    end
    
    local function startLoadingBar(isPoweringOn)
        if isAnimating then return end
        
        isAnimating = true
        local duration = ctx.roomAutomation.getTiming(isPoweringOn)
        local steps = 100
        local interval = duration / steps
        local currentStep = 0
        
        cleanup()
        
        loadingTimer = Timer.New()
        timeoutTimer = Timer.New()
        
        if controls.knbProgressBar then
            controls.knbProgressBar.Value = isPoweringOn and 0 or 100
        end
        if controls.txtProgressBar then
            controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
        end
        
        timeoutTimer.EventHandler = function()
            if isAnimating then
                debug("Loading bar timeout reached")
                isAnimating = false
                if loadingTimer then loadingTimer:Stop(); loadingTimer = nil end
                ctx.navigate(isPoweringOn and ctx.config.defaultActiveLayer or LAYERS.START)
            end
        end
        timeoutTimer:Start(300)
        
        loadingTimer.EventHandler = function()
            currentStep = currentStep + 1
            
            local progress = isPoweringOn and currentStep or (100 - currentStep)
            if controls.knbProgressBar then controls.knbProgressBar.Value = progress end
            if controls.txtProgressBar then controls.txtProgressBar.String = progress .. "%" end
            
            if currentStep >= steps then
                loadingTimer:Stop()
                timeoutTimer:Stop()
                isAnimating = false
                
                ctx.navigate(isPoweringOn and ctx.config.defaultActiveLayer or LAYERS.START)
            else
                loadingTimer:Start(interval)
            end
        end
        
        loadingTimer:Start(interval)
        debug("Loading bar started (" .. duration .. "s)")
    end
    
    return {
        startLoadingBar = startLoadingBar,
        cleanup = cleanup,
    }
end

-------------------[ Legend Module ]-------------------------
local function createLegendModule(ctx)
    local debug = createDebugger(ctx, "Legend")
    
    local arrUCILegends = {}
    local arrUCIUserLabels = {}
    
    local function updateLegends()
        for i, lbl in ipairs(arrUCILegends) do
            if lbl and arrUCIUserLabels[i] then
                setProp(lbl, "Legend", arrUCIUserLabels[i].String or "")
            end
        end
    end
    
    local function initialize()
        local legendControls = {
            "txtNav01", "txtNav02", "txtNav03", "txtNav04",
            "txtNav05", "txtNav06", "txtNav07", "txtNav08",
            "txtNav09", "txtNav10", "txtNav11", "txtNav12",
            "txtNavShutdown", "txtRoomNameNav", "txtRoomNameStart",
            "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03", "txtRouting04", "txtRouting05", "txtRoutingSources",
            "txtAudSrc01", "txtAudSrc02", "txtAudSrc03", "txtAudSrc04",
            "txtAudSrc05", "txtAudSrc06", "txtAudSrc07", "txtAudSrc08",
            "txtAudSrc09", "txtAudSrc10", "txtAudSrc11", "txtAudSrc12",
            "txtGainPGM", 
            "txtGain01", "txtGain02", "txtGain03", "txtGain04",
            "txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
            "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04",
        }
        
        local userLabelVariables = {
            "txtLabelNav01", "txtLabelNav02", "txtLabelNav03", "txtLabelNav04",
            "txtLabelNav05", "txtLabelNav06", "txtLabelNav07", "txtLabelNav08",
            "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12",
            "txtLabelNavShutdown", "txtLabelRoomNameNav", "txtLabelRoomNameStart",
            "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03", "txtLabelRouting04", "txtLabelRouting05", "txtLabelRoutingSources",
            "txtLabelAudSrc01", "txtLabelAudSrc02", "txtLabelAudSrc03", "txtLabelAudSrc04",
            "txtLabelAudSrc05", "txtLabelAudSrc06", "txtLabelAudSrc07", "txtLabelAudSrc08",
            "txtLabelAudSrc09", "txtLabelAudSrc10", "txtLabelAudSrc11", "txtLabelAudSrc12",
            "txtLabelGainPGM", 
            "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04",
            "txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
            "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04",
        }
        
        for i, controlName in ipairs(legendControls) do
            arrUCILegends[i] = Controls[controlName]
        end
        
        for i, varLabel in ipairs(userLabelVariables) do
            local variable = Uci.Variables[varLabel]
            if variable then
                arrUCIUserLabels[i] = variable
                variable.EventHandler = updateLegends
            end
        end
        
        debug("Legend arrays initialized with " .. #arrUCILegends .. " controls")
    end
    
    local function cleanup()
        for _, label in ipairs(arrUCIUserLabels) do
            if label then label.EventHandler = nil end
        end
    end
    
    return {
        initialize = initialize,
        updateLegends = updateLegends,
        cleanup = cleanup,
    }
end

-------------------[ Main UCI Factory ]----------------------
local function createUCI(config)
    if not validateControls() then
        print("ERROR: UCIController initialization failed - validation errors")
        return nil
    end
    
    local uciPage = config.uciPage
    local debugging = config.debugging ~= false
    
    -- Shared context for all modules
    local ctx = {
        uciPage = uciPage,
        debugging = debugging,
        config = {
            defaultActiveLayer = config.defaultActiveLayer or LAYERS.LAPTOP,
            defaultRoutingLayer = config.defaultRoutingLayer or 1,
            hiddenNavIndices = config.hiddenNavIndices or {},
        },
        state = {
            activeLayer = config.defaultActiveLayer or LAYERS.LAPTOP,
            isInitialized = false,
        },
        normalizedControls = normalizeControlArrays(),
    }
    
    local debug = createDebugger(ctx, "UCI")
    
    -- Layer-to-button mapping
    local layerToButtonMap = {
        [LAYERS.ALARM] = 1, [LAYERS.INCOMING_CALL] = 2, [LAYERS.START] = 3,
        [LAYERS.WARMING] = 4, [LAYERS.COOLING] = 5, [LAYERS.ROOM_CONTROLS] = 6,
        [LAYERS.PC] = 7, [LAYERS.LAPTOP] = 8, [LAYERS.WIRELESS] = 9,
        [LAYERS.ROUTING] = 10, [LAYERS.DIALER] = 11, [LAYERS.STREAM_MUSIC] = 12
    }
    
    local syncTimer = nil
    
    -- Forward declaration for navigate function
    local navigate
    
    -- Add navigate to context for modules that need it
    ctx.navigate = function(layer) navigate(layer) end
    
    -- Create modules (order matters - some depend on others)
    ctx.layer = createLayerModule(ctx)
    ctx.sublayer = createSublayerModule(ctx)
    ctx.routing = createRoutingModule(ctx)
    ctx.videoSwitcher = createVideoSwitcherModule(ctx)
    ctx.roomAutomation = createRoomAutomationModule(ctx)
    ctx.progress = createProgressModule(ctx)
    ctx.legend = createLegendModule(ctx)
    
    -- Interlock navigation buttons
    local function interlock()
        local navButtons = ctx.normalizedControls.navButtons
        if not navButtons then return end
        
        local activeButtonIndex = layerToButtonMap[ctx.state.activeLayer]
        
        for i, btn in ipairs(navButtons) do
            if btn then
                setProp(btn, "Boolean", i == activeButtonIndex)
            end
        end
        
        if ctx.state.activeLayer ~= LAYERS.ROUTING then
            ctx.routing.resetRoutingButtons()
        end
    end
    
    -- Navigation handler
    navigate = function(layerIndex)
        local previousLayer = ctx.state.activeLayer
        ctx.state.activeLayer = layerIndex
        
        -- Trigger video switcher for specific buttons
        if ctx.videoSwitcher.isEnabled() then
            local inputNumber = ctx.videoSwitcher.getInputMapping(layerIndex)
            if inputNumber then
                debug("Triggering video switch to input " .. inputNumber)
                ctx.videoSwitcher.switchToInput(inputNumber, layerIndex)
            end
        end
        
        ctx.layer.showLayer()
        interlock()
        debug("Layer changed from " .. previousLayer .. " to " .. layerIndex)
    end
    
    -- System control functions
    local function startSystem()
        ctx.roomAutomation.powerOn()
        ctx.progress.startLoadingBar(true)
        navigate(LAYERS.WARMING)
    end
    
    local function shutdownSystem()
        ctx.layer.updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        ctx.roomAutomation.powerOff()
        ctx.progress.startLoadingBar(false)
        navigate(LAYERS.COOLING)
    end
    
    -- Helper function to ensure system is on
    local function ensureSystemIsOn()
        local component = ctx.roomAutomation.getComponent()
        if component and component["ledSystemPower"] then
            if not component["ledSystemPower"].Boolean then
                startSystem()
            end
        end
    end
    
    -- Event handler registration
    local function registerEventHandlers()
        -- Navigation buttons
        forEach(ctx.normalizedControls.navButtons, function(i, btn)
            bind(btn, function() navigate(i) end)
        end)
        
        -- Routing buttons
        forEach(ctx.normalizedControls.routingButtons, function(i, btn)
            bind(btn, function() ctx.routing.routingButtonEventHandler(i) end)
        end)
        
        -- System controls
        local systemHandlers = {
            [controls.btnStartSystem] = startSystem,
            [controls.btnNavShutdown] = function()
                ctx.layer.updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
            end,
            [controls.btnShutdownCancel] = function()
                ctx.layer.updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
            end,
            [controls.btnShutdownConfirm] = shutdownSystem,
        }
        
        for ctrl, handler in pairs(systemHandlers) do
            if ctrl then bind(ctrl, handler) end
        end
        
        -- Help control pairs
        local helpPairs = {
            {open = controls.btnOpenHelpLaptop, close = controls.btnCloseHelpLaptop, handler = ctx.sublayer.updateLaptopHelpState},
            {open = controls.btnOpenHelpPC, close = controls.btnCloseHelpPC, handler = ctx.sublayer.updatePCHelpState},
            {open = controls.btnOpenHelpWireless, close = controls.btnCloseHelpWireless, handler = ctx.sublayer.updateWirelessHelpState},
            {open = controls.btnOpenHelpRouting, close = controls.btnCloseHelpRouting, handler = ctx.sublayer.updateRoutingHelpState},
            {open = controls.btnOpenHelpStreamMusic, close = controls.btnCloseHelpStreamMusic, handler = ctx.sublayer.updateStreamMusicHelpState},
        }
        
        for _, pair in ipairs(helpPairs) do
            bindPairedControls(pair.open, pair.close, pair.handler)
        end
        
        -- Pin state handlers
        local pinHandlers = {
            [controls.pinLEDUSBLaptop] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.LAPTOP)
                else ctx.sublayer.updateConferenceState() end
            end,
            [controls.pinLEDUSBPC] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.PC)
                else ctx.sublayer.updateConferenceState() end
            end,
            [controls.pinLEDOffHookLaptop] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.LAPTOP) end
            end,
            [controls.pinLEDOffHookPC] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.PC) end
            end,
            [controls.pinLEDHDMI01Active] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.LAPTOP) end
            end,
            [controls.pinLEDHDMI02Active] = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(); navigate(LAYERS.PC) end
            end,
            [controls.pinLEDPresetSaved] = ctx.sublayer.updatePresetSavedState,
            [controls.pinLEDHDMI01Connect] = ctx.sublayer.updateHDMI01State,
            [controls.pinLEDHDMI02Connect] = ctx.sublayer.updateHDMI02State,
            [controls.pinLEDACPRBypassActive] = ctx.sublayer.updateACPRBypassState,
            [controls.pinCallActive] = ctx.sublayer.updateCallActiveState,
        }
        
        for ctrl, handler in pairs(pinHandlers) do
            if ctrl then bind(ctrl, handler) end
        end
        
        debug("Event handlers registered")
    end
    
    -- Sync timer management
    local function startSyncTimer()
        local component = ctx.roomAutomation.getComponent()
        if not component then
            debug("Room Controls sync disabled (component not available)")
            return
        end
        
        syncTimer = Timer.New()
        syncTimer.EventHandler = function()
            ctx.roomAutomation.syncRoomControlsState()
            syncTimer:Start(1)
        end
        syncTimer:Start(1)
        debug("Room Controls state synchronization enabled (1s interval)")
    end
    
    local function stopSyncTimer()
        if syncTimer then
            syncTimer:Stop()
            syncTimer = nil
            debug("Room Controls sync timer stopped")
        end
    end
    
    -- Initialization
    local function init()
        ctx.layer.resetLayerStates()
        ctx.legend.initialize()
        ctx.roomAutomation.initializeComponent()
        ctx.videoSwitcher.initialize()
        
        -- Sync with Room Automation state if available
        if mySystemController and mySystemController.state then
            local systemPowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean
            if systemPowerState then
                if mySystemController.state.isWarming then
                    ctx.state.activeLayer = LAYERS.WARMING
                    ctx.progress.startLoadingBar(true)
                else
                    ctx.state.activeLayer = ctx.config.defaultActiveLayer
                end
            else
                ctx.state.activeLayer = LAYERS.START
            end
            debug("Synchronized with Room Automation state")
        else
            ctx.state.activeLayer = LAYERS.START
            debug("Using default initialization")
        end
        
        -- Hide specified navigation buttons
        for _, index in ipairs(ctx.config.hiddenNavIndices) do
            local btn = controls["btnNav" .. string.format("%02d", index)]
            if btn then
                btn.Visible = false
                debug("Hidden navigation button: btnNav" .. string.format("%02d", index))
            end
        end
        
        ctx.layer.showLayer()
        interlock()
        ctx.legend.updateLegends()
        startSyncTimer()
        
        debug("UCI Initialized for " .. uciPage)
        ctx.state.isInitialized = true
    end
    
    -- Cleanup
    local function cleanup()
        stopSyncTimer()
        ctx.progress.cleanup()
        ctx.legend.cleanup()
        debug("UCI Controller cleanup completed")
    end
    
    -- Register events and initialize
    registerEventHandlers()
    init()
    
    -- Public API
    return {
        navigate = navigate,
        cleanup = cleanup,
        startSyncTimer = startSyncTimer,
        stopSyncTimer = stopSyncTimer,
        
        -- Module access for advanced use
        layer = ctx.layer,
        sublayer = ctx.sublayer,
        routing = ctx.routing,
        videoSwitcher = ctx.videoSwitcher,
        roomAutomation = ctx.roomAutomation,
        progress = ctx.progress,
        legend = ctx.legend,
        
        -- State access (read-only pattern)
        getActiveLayer = function() return ctx.state.activeLayer end,
        isInitialized = function() return ctx.state.isInitialized end,
        
        -- Constants
        LAYERS = LAYERS,
    }
end

-------------------[ Instance Creation ]---------------------
myUCI = createUCI({
    uciPage = Uci.Variables.txtUCIPageName.String,
    defaultRoutingLayer = tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 4,
    defaultActiveLayer = tonumber(Uci.Variables.numDefaultActiveLayer.Value) or LAYERS.LAPTOP,
    hiddenNavIndices = {},
    debugging = true,
})

if myUCI then
    print("✓ UCIController (Functional) created successfully!")
    print("Event-driven Room Controls synchronization is active")
    _G.myUCI = myUCI
    _G.LAYERS = LAYERS
else
    print("✗ ERROR: UCIController NOT created.")
end

------------------[ Public API ]-----------------------------
--[[
Public API:
    myUCI.navigate(layerIndex)          -- Navigate to a layer
    myUCI.cleanup()                     -- Clean up resources
    myUCI.startSyncTimer()              -- Start room controls sync
    myUCI.stopSyncTimer()               -- Stop room controls sync
    
    myUCI.getActiveLayer()              -- Get current active layer
    myUCI.isInitialized()               -- Check if initialized
    
    -- Module access
    myUCI.layer.showLayer()
    myUCI.sublayer.updateCallActiveState()
    myUCI.routing.showRoutingLayer()
    myUCI.videoSwitcher.switchToInput(inputNumber, uciButton)
    myUCI.roomAutomation.powerOn()
    myUCI.roomAutomation.powerOff()
    myUCI.progress.startLoadingBar(isPoweringOn)
    
    -- Layer constants
    LAYERS.ALARM, LAYERS.START, LAYERS.LAPTOP, etc.

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController ledSystemPower status (1s interval)
    - Uses ledSystemPower as authoritative status indicator
    - Updates UCI layers and progress bar when power state changes externally
]]
