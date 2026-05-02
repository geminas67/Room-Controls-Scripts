--[[
  HDMI Port Controller — Q-SYS script for decoder HDMI port management
  Author: Nikolas Smith, Q-SYS
  Date: 2026-04-09
  Version: 1.0
  Firmware Req: 10.2.0
  Description: Enables/disables decoder HDMI ports from UCI layer selector state and
  encoder hot-plug detection (event-driven).
--]]

-------------------[ Component References ]-------------------
local devDecoder19 = Component.New('devDecoder19')
local devDecoder20 = Component.New('devDecoder20')
local devEncoder09 = Component.New('devEncoder09')
local devEncoder10 = Component.New('devEncoder10')
local uciEmc = Component.New('EMC TR UCI Layer Selector')
local uciRmA = Component.New('Rm-A-UCI Layer Selector')
local uciRmB = Component.New('Rm-B-UCI Layer Selector')

-------------------[ Configuration ]-------------------

local pulseSeconds = 0.2

-- path index 1 = DEC-19, 2 = DEC-20 — OR of UCI layers must be true with encoder HotPlugDetect
local hdmiPaths = {
    {
        encoder = devEncoder09,
        decoder = devDecoder19,
        routeCheck = function()
            return uciEmc['selector.5'].Boolean or uciRmA['selector.4'].Boolean
        end,
        orMsg = 'HDMI Port OR - EMC Layer 6 / Rm-A Layer 5 Active and Hot Plug Detected',
        label = 'DEC-19',
    },
    {
        encoder = devEncoder10,
        decoder = devDecoder20,
        routeCheck = function()
            return uciEmc['selector.7'].Boolean or uciRmB['selector.4'].Boolean
        end,
        orMsg = 'HDMI Port OR - EMC Layer 8 / Rm-B Layer 5 Active and Hot Plug Detected',
        label = 'DEC-20',
    },
}

local handlerRegistrations = {
    { comp = devEncoder09, ctrl = 'HotPlugDetect', log = 'Hot Plug Detect Rm A change', path = 1 },
    { comp = devEncoder10, ctrl = 'HotPlugDetect', log = 'Hot Plug Detect Rm B change', path = 2 },
    { comp = uciEmc, ctrl = 'selector_5', log = 'EMC Selector 6 change', path = 1 },
    { comp = uciRmA, ctrl = 'selector_4', log = 'Rm-A Selector 5 change', path = 1 },
    { comp = uciEmc, ctrl = 'selector_7', log = 'EMC Selector 8 change', path = 2 },
    { comp = uciRmB, ctrl = 'selector_4', log = 'Rm-B Selector 5 change', path = 2 },
}

local function applyHdmiPath(pathIdx)
    local path = hdmiPaths[pathIdx]
    local wantOn = path.routeCheck() and path.encoder['HotPlugDetect'].Boolean
    if wantOn then
        print(path.orMsg)
        path.decoder['HdmiPortOn'].Boolean = true
        Timer.CallAfter(function()
            path.decoder['HdmiPortOn'].Boolean = false
        end, pulseSeconds)
        print('HDMI Port On - ' .. path.label)
    else
        path.decoder['HdmiPortOff'].Boolean = true
        Timer.CallAfter(function()
            path.decoder['HdmiPortOff'].Boolean = false
        end, pulseSeconds)
        print('HDMI Port Off - ' .. path.label)
    end
end

for _, reg in ipairs(handlerRegistrations) do
    reg.comp[reg.ctrl].EventHandler = function()
        print(reg.log)
        applyHdmiPath(reg.path)
    end
end
