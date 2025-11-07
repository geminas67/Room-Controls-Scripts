--[[
    RS232 Receive Monitor
    Description: Monitors RS232 receive data from devDecoderXX and displays it in strRS232Rx control
]]

-------------------[ Component References ]-------------------
local components = {
    devDecoder = Component.New('devDecoder35')
}

-------------------[ Control References ]-------------------
local controls = {
    strRS232Rx = Controls.strRS232Rx
}

-------------------[ Utility Functions ]-------------------
local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

-------------------[ Event Handlers ]-------------------
local function registerEventHandlers()
    local decoder = components.devDecoder
    local rs232Rx = decoder and decoder['Rs232Rx']
    local strControl = controls.strRS232Rx
    
    if rs232Rx and strControl then
        rs232Rx.EventHandler = function(ctl)
            if ctl and ctl.String then
                setProp(strControl, "String", ctl.String)
            end
        end
        print("RS232RxMonitor: Event handler registered for devDecoder.Rs232Rx")
    else
        if not decoder then
            print("ERROR: RS232RxMonitor - devDecoder component not found")
        end
        if not rs232Rx then
            print("ERROR: RS232RxMonitor - devDecoder.Rs232Rx control not found")
        end
        if not strControl then
            print("ERROR: RS232RxMonitor - strRS232Rx control not found")
        end
    end
end

-------------------[ Initialization ]-------------------
local function funcInit()
    registerEventHandlers()
    print("RS232RxMonitor initialized")
end

-------------------[ Main Execution ]-------------------
funcInit()

